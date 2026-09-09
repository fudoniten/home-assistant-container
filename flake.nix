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
    # Single nixpkgs, tracking the release. There is deliberately no
    # `nixpkgsUnstable` here: a second nixpkgs instance means a second copy of
    # everything below it in the closure, and any overlay applied to it (this
    # flake used to pin `python3` to 3.13 in one) puts every downstream
    # derivation outside cache.nixos.org, so the consuming host rebuilds it
    # all from source. Take packages from the same `nixpkgs` the host uses.
    nixpkgs.url = "nixpkgs/nixos-26.05";
    utils.url = "github:numtide/flake-utils";

    # Arion - Nix-based Docker Compose manager
    # Provides declarative container orchestration integrated with NixOS
    arion.url = "github:hercules-ci/arion";

    # Custom Home Assistant component: Node-Red integration
    # Version pinned to v4.2.3 for stability -- keep `version` in the overlay
    # below in step with this ref by hand. buildHomeAssistantComponent only
    # checks the manifest's *requirements*, not its version, so a mismatch is
    # silent: it just mislabels the derivation (this said 4.1.2 for a 4.2.3 src).
    # flake=false means we just want the source, not to evaluate it as a flake
    hass-node-red = {
      url = "github:zachowj/hass-node-red?ref=v4.2.3";
      flake = false;
    };

    # Custom Home Assistant component: No Longer Evil thermostat
    # Integrates jailbroken Nest thermostats via the No Longer Evil cloud API
    nolongerevil = {
      url = "github:patricktr/NoLongerEvil-HomeAssistant?ref=v1.0.1";
      flake = false;
    };
  };

  # ============================================================================
  # Outputs
  # ============================================================================

  outputs = { self, nixpkgs, utils, arion, ... }@inputs:

    # Build packages only for Linux systems
    # Home Assistant containers are Linux-only (primarily x86_64)
    utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      # Build through the overlay rather than beside it, so `packages` and
      # `pkgs.home-assistant-local-components` are the same derivations and
      # there is one place that says which version each component is.
      let pkgs = nixpkgs.legacyPackages."${system}".extend self.overlays.default;
      in {
        # Custom Home Assistant component packages
        # These are built from external GitHub repositories
        packages = {
          inherit (pkgs.home-assistant-local-components) nodered nolongerevil;
        };

        # Checks for CI/CD
        # These validate that the packages build correctly
        checks = {
          # Verify that all custom components build successfully
          inherit (self.packages.${system}) nodered nolongerevil;
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

          # No aiounittest workaround here, deliberately. nixpkgs still marks
          # aiounittest `disabled = pythonAtLeast "3.14"` while home-assistant
          # requires 3.14, which is what used to make anything reaching it
          # through home-assistant's Python scope fail to *evaluate* -- the
          # reason this flake carried its own nixpkgs and an
          # `home-assistant.override { packageOverrides = ...; }`.
          #
          # On nixos-26.05 nothing in that path reaches aiounittest any more.
          # Checked by evaluating home-assistant with the full extraComponents
          # and extraPackages list, all three home-assistant-custom-components
          # and all eight custom-lovelace-modules used by this module: they
          # evaluate unpatched, and patching aiounittest gives byte-identical
          # derivation paths. If a future bump reintroduces the failure, patch
          # `python314Packages` in an overlay here rather than overriding
          # home-assistant alone -- home-assistant-custom-components is scoped
          # off `home-assistant.python3Packages`, so a package-level override
          # fixes home-assistant and leaves the component sets broken.

          # Build the local components from the *consuming* package set
          # (`final`), not from this flake's own `nixpkgs`. Reading them out of
          # `self.packages.<system>` ignored final/prev entirely, so a consumer
          # got components built against whatever nixpkgs this flake happened
          # to be locked to -- a different Python set from the home-assistant
          # actually running them, and a second nixpkgs in the closure.
          homeAssistantComponents = final: _prev: {
            home-assistant-local-components = {
              # Node-Red integration component
              # Allows creating visual automation flows that integrate with Home Assistant
              nodered = final.callPackage ./hass-node-red.nix {
                inherit (inputs) hass-node-red;
                version = "4.2.3";
              };

              # No Longer Evil thermostat component
              # Integrates jailbroken Nest thermostats via the No Longer Evil cloud API
              nolongerevil = final.callPackage ./nolongerevil.nix {
                inherit (inputs) nolongerevil;
                version = "1.0.1";
              };
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
            imports = [ arion.nixosModules.arion ./home-assistant-container.nix ];
          };
        };
      };
}
