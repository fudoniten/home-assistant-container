{ extended-openai-conversation, lib, fetchFromGithub
, buildHomeAssistantComponent, python312Packages, version, ... }:

buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = let
    openai = python312Packages.openai.overrideAttrs (oldAttrs: rec {
      version = "1.3.8";
      src = fetchFromGithub {
        owner = "openai";
        repo = "openai-python";
        rev = "ref/tags/v${version}";
        hash = "sha256-yU0XWEDYl/oBPpYNFg256H0Hn5AaJiP0vOQhbRLnAxQ=";
      };
    });
  in [ openai ];
}
