{ openai_tts, buildHomeAssistantComponent, version, ... }:

buildHomeAssistantComponent {
  src = openai_tts;
  owner = "sfortis";
  domain = "openai_tts";
  version = version;
}
