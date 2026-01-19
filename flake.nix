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
    # NixOS 25.05 stable channel for core packages
    nixpkgs.url = "nixpkgs/nixos-25.05";

    # Flake utilities for multi-system support
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

    # Build packages for all default systems (x86_64-linux, aarch64-linux, etc.)
    utils.lib.eachDefaultSystem (system:
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
          # Note: version string doesn't match git ref (uses latest from main)
          openai_tts = pkgs.callPackage ./openai_tts.nix {
            inherit openai_tts;
            version = "v3.4b5";  # Display version (not git ref)
          };
        };
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
