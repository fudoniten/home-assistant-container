{ extended-openai-conversation, lib, pythonPackages, ... }:

with pythonPackages;
buildPythonPackage rec {
  name = "extended-openai-conversation";

  src = extended-openai-conversation;

  propagatedBuildInputs = with pythonPackages; [
    bs4
    homeassistant
    openai
    voluptuous
  ];

  meta = with lib; {
    description =
      "Enhanced OpenAI conversational abilities for home assistant.";
    homepage = "https://github.com/jekalmin/extended_openai_conversation";
  };
}
