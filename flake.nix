{
  description = "Home Assistant running in a container";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    utils.url = "github:numtide/flake-utils";
    arion.url = "github:hercules-ci/arion";
    extended-openai-conversation = {
      url = "github:jekalmin/extended_openai_conversation";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, utils, arion, extended-openai-conversation, ... }@inputs:
    utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages."${system}";
      in {
        package = rec {
          extended_openai_conversation =
            pkgs.callPackage ./extended-openai-conversation.nix {
              inherit extended-openai-conversation;
            };
        };
      }) // {
        overlays = rec {
          default = homeAssistantComponents;
          homeAssistantComponents = final: prev:
            let localPackages = self.packages."${prev.system}";
            in {
              home-assistant-custom-components = {
                inherit (localPackages) extended_openai_conversation;
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
