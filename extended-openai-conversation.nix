{ extended-openai-conversation, lib, python3Packages, ... }:

with python3Packages;
buildPythonPackage rec {
  name = "extended-openai-conversation";

  src = extended-openai-conversation;

  propagatedBuildInputs = with pythonPackages; [
    beautifulsoup4
    openai
    voluptuous
  ];

  meta = with lib; {
    description =
      "Enhanced OpenAI conversational abilities for home assistant.";
    homepage = "https://github.com/jekalmin/extended_openai_conversation";
  };
}
