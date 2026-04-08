# No Longer Evil Home Assistant Integration
#
# This builds the No Longer Evil custom component for Home Assistant, which
# integrates jailbroken Nest thermostats (running No Longer Evil firmware)
# via the No Longer Evil cloud API.
#
# Features:
# - Temperature management and HVAC mode control
# - Fan operation and away mode
# - Support for multiple devices per account
# - Requires a No Longer Evil API key (read + write scopes)
#
# Source: https://github.com/patricktr/NoLongerEvil-HomeAssistant

{ nolongerevil, buildHomeAssistantComponent, version, python3Packages, ... }:

buildHomeAssistantComponent {
  src = nolongerevil;
  owner = "patricktr";
  domain = "nolongerevil";
  version = version;

  propagatedBuildInputs = with python3Packages; [ aiohttp ];
}
