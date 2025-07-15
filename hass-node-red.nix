{ hass-node-red, buildHomeAssistantComponent, version, ... }:

buildHomeAssistantComponent {
  src = hass-node-red;
  owner = "zachowj";
  domain = "nodered";
  version = version;
}
