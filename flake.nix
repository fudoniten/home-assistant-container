{
  description = "Home Assistant running in a container";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    arion.url = "github:hercules-ci/arion";
  };

  outputs = { self, nixpkgs, arion, ... }: {
    nixosModules = rec {
      default = homeAssistantContainer;
      homeAssistantContainer = { ... }: {
        imports = [ arion.nixosModules.arion ./home-assistant-container.nix ];
      };
    };
  };
}
