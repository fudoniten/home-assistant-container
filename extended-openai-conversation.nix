{ extended-openai-conversation, lib, buildHomeAssistantComponent
, python3Packages, version, ... }:

buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
}
