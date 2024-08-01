{ extended-openai-conversation, lib, buildHomeAssistantComponent
, python312Packages, version, openai, ... }:

buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = [ openai ];
}
