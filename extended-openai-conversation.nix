# Extended OpenAI Conversation Custom Component
#
# This builds the Extended OpenAI Conversation component for Home Assistant,
# which provides enhanced AI conversation capabilities with function calling support.
#
# Source: https://github.com/jekalmin/extended_openai_conversation

{ extended-openai-conversation, lib, fetchFromGitHub
, buildHomeAssistantComponent, python313Packages, version, ... }:

let
  # Custom build of OpenAI Python library
  #
  # We build this from source instead of using python313Packages.openai because
  # the nixpkgs version has dependency patching issues that break compatibility
  # with the Extended OpenAI Conversation component.
  #
  # This approach:
  # - Uses PEP 517 build system (pyproject.toml)
  # - Skips nixpkgs dependency patching that causes build failures
  # - Pins to version 1.13.3 for stability
  openai = python313Packages.buildPythonPackage rec {
    pname = "openai";
    version = "1.13.3";
    format = "pyproject";

    src = fetchFromGitHub {
      owner = "openai";
      repo = "openai-python";
      rev = "refs/tags/v${version}";
      hash = "sha256-8SHXUrPLZ7lgvB0jqZlcvKq5Zv2d2UqXjJpgiBpR8P8=";
    };

    # Build system dependencies
    nativeBuildInputs = with python313Packages; [ hatchling ];

    # Runtime dependencies required by openai library
    propagatedBuildInputs = with python313Packages; [
      anyio
      distro
      httpx
      pydantic
      sniffio
      tqdm
      typing-extensions
    ];

    # Skip nixpkgs dependency patching which breaks the build
    # The default patching tries to update dependency versions in pyproject.toml
    # but this causes compatibility issues with the component
    postPatch = ''
      echo "Skipping fragile dependency patching step"
    '';
  };

# Build the Extended OpenAI Conversation component with our custom openai package
in buildHomeAssistantComponent {
  src = extended-openai-conversation;
  owner = "jekalmin";
  domain = "extended_openai_conversation";
  version = version;
  propagatedBuildInputs = [ openai ];
}
