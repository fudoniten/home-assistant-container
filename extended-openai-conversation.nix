{ extended-openai-conversation, lib, fetchFromGitHub
, buildHomeAssistantComponent, python312Packages, version, ... }:

buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = let
    openai = python312Packages.openai.overrideAttrs (oldAttrs: rec {
      version = "1.3.8";
      src = fetchFromGitHub {
        owner = "openai";
        repo = "openai-python";
        rev = "refs/tags/v${version}";
        hash = "sha256-yU0XWEDYl/oBPpYNFg256H0Hn5AaJiP0vOQhbRLnAxQ=";
      };
      disabledTests = oldAttrs.disabledTests ++ [
        "test_retrying_timeout_errors_doesnt_leak"
        "test_retrying_status_errors_doesnt_leak"
      ];
    });
  in [ openai ];
}
