{ extended-openai-conversation, lib, fetchFromGitHub
, buildHomeAssistantComponent, python313Packages, version, ... }:

let
  # openai = python313Packages.openai.overrideAttrs (oldAttrs: rec {
  #   version = "1.13.3";
  #   src = fetchFromGitHub {
  #     owner = "openai";
  #     repo = "openai-python";
  #     rev = "refs/tags/v${version}";
  #     hash = "sha256-8SHXUrPLZ7lgvB0jqZlcvKq5Zv2d2UqXjJpgiBpR8P8=";
  #   };
  # disabledTests = oldAttrs.disabledTests ++ [
  #   "test_retrying_timeout_errors_doesnt_leak"
  #   "test_retrying_status_errors_doesnt_leak"
  # ];
  # });

  openai = python313Packages.buildPythonPackage rec {
    pname = "openai";
    version = "1.13.3";
    format = "pyproject"; # This tells Nix to use the modern PEP 517 builder

    src = fetchFromGitHub {
      owner = "openai";
      repo = "openai-python";
      rev = "refs/tags/v${version}";
      hash = "sha256-8SHXUrPLZ7lgvB0jqZlcvKq5Zv2d2UqXjJpgiBpR8P8=";
    };

    nativeBuildInputs = with python313Packages; [ hatchling ];

    propagatedBuildInputs = with py; [
      anyio
      distro
      httpx
      pydantic
      sniffio
      tqdm
      typing-extensions
    ];

    # Optional: skip tests if they fail
    # doCheck = false;

    # Avoid Nixpkgs default dependency patching, which is breaking your build
    postPatch = ''
      echo "Skipping fragile dependency patching step"
    '';
  };

in buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = [ openai ];
}
