{ extended-openai-conversation, lib, fetchFromGitHub
, buildHomeAssistantComponent, python3, python3Packages, version, ... }:

let
  openai = python3.pkgs.buildPythonPackage rec {
    pname = "openai";
    version = "1.13.3";
    format = "setuptools";

    src = fetchFromGitHub {
      owner = "openai";
      repo = "openai-python";
      rev = "refs/tags/v${version}";
      hash = "sha256-8SHXUrPLZ7lgvB0jqZlcvKq5Zv2d2UqXjJpgiBpR8P8=";
    };

    doCheck = false;
  };

in buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = [ openai ];
}
