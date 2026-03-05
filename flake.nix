# Home Assistant Container Nix Flake
#
# This flake provides a NixOS module for running Home Assistant and related
# services in Docker containers managed by Arion.
#
# Outputs:
# - packages: Custom Home Assistant components (nodered, openai_tts)
# - overlays: Makes local packages available as home-assistant-local-components
# - nixosModules: The homeAssistantContainer module for NixOS configurations
#
# Usage:
#   Add this flake to your inputs and import the nixosModule:
#   inputs.home-assistant-container.nixosModules.default

{
  description = "Home Assistant running in a container";

  # ============================================================================
  # Inputs
  # ============================================================================

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    nixpkgsUnstable.url = "nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";

    # Arion - Nix-based Docker Compose manager
    # Provides declarative container orchestration integrated with NixOS
    arion.url = "github:hercules-ci/arion";

    # Custom Home Assistant component: Node-Red integration
    # Version pinned to v4.1.2 for stability
    # flake=false means we just want the source, not to evaluate it as a flake
    hass-node-red = {
      url = "github:zachowj/hass-node-red?ref=v4.1.2";
      flake = false;
    };

    # Custom Home Assistant component: OpenAI TTS
    # Uses latest commit from main branch
    openai_tts = {
      url = "github:sfortis/openai_tts";
      flake = false;
    };
  };

  # ============================================================================
  # Outputs
  # ============================================================================

  outputs =
    { self, nixpkgs, utils, arion, hass-node-red, openai_tts, ... }@inputs:

    # Build packages only for Linux systems
    # Home Assistant containers are Linux-only (primarily x86_64)
    utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let pkgs = nixpkgs.legacyPackages."${system}";
      in {
        # Custom Home Assistant component packages
        # These are built from external GitHub repositories
        packages = {
          # Node-Red integration component
          # Allows creating visual automation flows that integrate with Home Assistant
          nodered = pkgs.callPackage ./hass-node-red.nix {
            inherit hass-node-red;
            version = "4.1.2";
          };

          # OpenAI TTS component
          # Provides text-to-speech using OpenAI's voice models
          # FIXME: Version string doesn't match git ref
          # The input uses latest from main branch, but version is set to v3.4b5
          # Should either:
          #   1. Pin input to tag: url = "github:sfortis/openai_tts?ref=v3.4b5"
          #   2. Use dynamic version: version = "unstable-${openai_tts.shortRev}"
          openai_tts = pkgs.callPackage ./openai_tts.nix {
            inherit openai_tts;
            version = "v3.4b5";
          };
        };

        # Checks for CI/CD
        # These validate that the packages build correctly
        checks = {
          # Verify that both custom components build successfully
          inherit (self.packages.${system}) nodered openai_tts;
        };

        # Formatter for `nix fmt`
        # Use nixfmt-rfc-style for consistent Nix code formatting
        formatter = pkgs.nixfmt-rfc-style;
      }) // {
        # ======================================================================
        # Overlays
        # ======================================================================
        # Overlays make our custom packages available in nixpkgs
        # Users can access them via pkgs.home-assistant-local-components

        overlays = rec {
          default = homeAssistantComponents;

          homeAssistantComponents = final: prev:
            let localPackages = self.packages."${prev.system}";
            in {
              # Inject our custom components into a new attribute set
              # This allows the main module to access them via pkgs
              home-assistant-local-components = {
                inherit (localPackages) nodered openai_tts;
              };
            };
        };

        # ======================================================================
        # NixOS Modules
        # ======================================================================
        # The main module that users import to enable Home Assistant containers

        nixosModules = rec {
          default = homeAssistantContainer;

          homeAssistantContainer = { ... }: {
            # Apply our overlay so the module can access local components
            config.nixpkgs.overlays = [ self.overlays.default ];

            # Import required modules:
            # 1. Arion - for container orchestration
            # 2. Our main module - defines services.homeAssistantContainer options
            imports = [
              arion.nixosModules.arion
              (import ./home-assistant-container.nix { inherit inputs; })
            ];
          };
        };
      };
}
