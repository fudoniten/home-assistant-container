{ hass-node-red, lib, fetchFromGitHub, buildHomeAssistantComponent
, python312Packages, version, ... }:

buildHomeAssistantComponent {
  src = hass-node-red;
  owner = "zachowj";
  domain = "hass-node-red";
  version = version;
}
