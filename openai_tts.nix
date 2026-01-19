# OpenAI Text-to-Speech Custom Component
#
# This builds the OpenAI TTS component for Home Assistant, which provides
# text-to-speech using OpenAI's voice models.
#
# Features:
# - High-quality neural voice synthesis using OpenAI's API
# - Multiple voice options (alloy, echo, fable, onyx, nova, shimmer)
# - Support for different voice models (tts-1, tts-1-hd)
# - Integrates with Home Assistant's TTS platform
#
# Note: Requires an OpenAI API key to function
# Alternative: Consider using Piper (included in this flake) for offline TTS
#
# Source: https://github.com/sfortis/openai_tts

{ openai_tts, buildHomeAssistantComponent, version, ... }:

buildHomeAssistantComponent {
  src = openai_tts;
  owner = "sfortis";
  domain = "openai_tts";
  version = version;
}
