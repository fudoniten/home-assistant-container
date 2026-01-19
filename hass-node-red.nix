# Node-Red Home Assistant Integration
#
# This builds the Node-Red custom component for Home Assistant, which allows
# creating visual flow-based automations and integrations using Node-Red.
#
# The component provides:
# - Bidirectional communication between Home Assistant and Node-Red
# - Trigger automations from Home Assistant events
# - Control Home Assistant entities from Node-Red flows
# - Access to Home Assistant state and services
#
# Source: https://github.com/zachowj/hass-node-red
# Version: 4.1.2 (pinned in flake.nix)

{ hass-node-red, buildHomeAssistantComponent, version, ... }:

buildHomeAssistantComponent {
  src = hass-node-red;
  owner = "zachowj";
  domain = "nodered";
  version = version;
}
