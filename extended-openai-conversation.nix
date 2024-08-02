{ extended-openai-conversation, lib, buildHomeAssistantComponent
, python312Packages, version, pkgsUnstable, ... }:

buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = [ pkgsUnstable.python312Packages.openai ];
}
