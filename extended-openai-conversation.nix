{ extended-openai-conversation, lib, buildHomeAssistantComponent
, python312Packages, version, ... }:

buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = with python312Packages; [ openai ];
}
