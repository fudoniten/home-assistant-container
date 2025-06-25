{ extended-openai-conversation, lib, fetchFromGitHub
, buildHomeAssistantComponent, python3Packages, version, ... }:

buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = let
    openai = python3Packages.openai.overrideAttrs (oldAttrs: rec {
      version = "1.13.3";
      src = fetchFromGitHub {
        owner = "openai";
        repo = "openai-python";
        rev = "refs/tags/v${version}";
        hash = "sha256-8SHXUrPLZ7lgvB0jqZlcvKq5Zv2d2UqXjJpgiBpR8P8=";
      };
      disabledTests = oldAttrs.disabledTests ++ [
        "test_retrying_timeout_errors_doesnt_leak"
        "test_retrying_status_errors_doesnt_leak"
      ];
    });
  in [ openai python3Packages ];
}
