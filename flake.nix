{
  description = "Home Assistant running in a container";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    utils.url = "github:numtide/flake-utils";
    arion.url = "github:hercules-ci/arion";
    hass-node-red = {
      url = "github:zachowj/hass-node-red?ref=v4.1.2";
      flake = false;
    };
    openai_tts = {
      url =
        "github:sfortis/openai_tts/baa7d2142665d1ea29ffbec2132dbb8b91529e25";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, utils, arion, hass-node-red, openai_tts, ... }@inputs:
    utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages."${system}";
      in {
        packages = {
          nodered = pkgs.callPackage ./hass-node-red.nix {
            inherit hass-node-red;
            version = "4.1.2";
          };

          openai_tts = pkgs.callPackage ./openai_tts.nix {
            inherit openai_tts;
            version = "v3.4b5";
          };
        };
      }) // {
        overlays = rec {
          default = homeAssistantComponents;
          homeAssistantComponents = final: prev:
            let localPackages = self.packages."${prev.system}";
            in {
              home-assistant-local-components = {
                inherit (localPackages) nodered openai_tts;
              };
            };
        };

        nixosModules = rec {
          default = homeAssistantContainer;
          homeAssistantContainer = { ... }: {
            config.nixpkgs.overlays = [ self.overlays.default ];
            imports = [
              arion.nixosModules.arion
              (import ./home-assistant-container.nix { inherit inputs; })
            ];
          };
        };
      };
}
