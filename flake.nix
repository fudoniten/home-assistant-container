{
  description = "Home Assistant running in a container";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    utils.url = "github:numtide/flake-utils";
    arion.url = "github:hercules-ci/arion";
    extended-openai-conversation = {
      url = "github:jekalmin/extended_openai_conversation?ref=1.0.5";
      flake = false;
    };
    hass-node-red = {
      url = "github:zachowj/hass-node-red?ref=v4.0.1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, utils, arion, extended-openai-conversation
    , hass-node-red, ... }@inputs:
    utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages."${system}";
      in {
        packages = rec {
          extended_openai_conversation =
            pkgs.callPackage ./extended-openai-conversation.nix {
              inherit extended-openai-conversation;
              version = "1.0.5";
            };
          nodered = pkgs.callPackage ./hass-node-red.nix {
            inherit hass-node-red;
            version = "4.0.1";
          };
        };
      }) // {
        overlays = rec {
          default = homeAssistantComponents;
          homeAssistantComponents = final: prev:
            let localPackages = self.packages."${prev.system}";
            in {
              home-assistant-local-components = {
                inherit (localPackages) extended_openai_conversation nodered;
              };
            };
        };

        nixosModules = rec {
          default = homeAssistantContainer;
          homeAssistantContainer = { ... }: {
            config.nixpkgs.overlays = [ self.overlays.default ];
            imports =
              [ arion.nixosModules.arion ./home-assistant-container.nix ];
          };
        };
      };
}
