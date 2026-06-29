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

{ nolongerevil, buildHomeAssistantComponent, version, home-assistant, ... }:

buildHomeAssistantComponent {
  src = nolongerevil;
  owner = "patricktr";
  domain = "nolongerevil";
  version = version;

  # Source aiohttp from Home Assistant's own Python package set rather than the
  # top-level python3Packages. buildHomeAssistantComponent builds the component
  # against home-assistant.python3Packages (Python 3.14 in nixos-26.05), while
  # the top-level python3Packages still defaults to Python 3.13. Pulling aiohttp
  # from python3Packages produced a Python version mismatch between the
  # component and its propagated dependency.
  propagatedBuildInputs = with home-assistant.python3Packages; [ aiohttp ];
}
