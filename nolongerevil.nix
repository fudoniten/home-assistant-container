# No Longer Evil Home Assistant Integration
#
# This builds the No Longer Evil custom component for Home Assistant, which
# integrates jailbroken Nest thermostats (running No Longer Evil firmware)
# via the No Longer Evil cloud API. It is what this deployment uses in place
# of the built-in `nest` integration, whose SDM API does not support
# thermostats this old.
#
# Features:
# - Temperature management and HVAC mode control
# - Fan operation and away mode
# - Support for multiple devices per account
# - Requires a No Longer Evil API key (read + write scopes)
#
# Source: https://github.com/patricktr/NoLongerEvil-HomeAssistant

{ lib, nolongerevil, buildHomeAssistantComponent, version, aiohttp, ... }:

buildHomeAssistantComponent {
  src = nolongerevil;
  owner = "patricktr";
  domain = "nolongerevil";
  inherit version;

  # Unqualified, per nixpkgs' custom-component packaging guidelines: the
  # overlay calls this file through `home-assistant.python3Packages.callPackage`
  # (as nixpkgs does for its own custom components), so `aiohttp` already comes
  # from Home Assistant's Python set rather than the top-level one, which on
  # 26.05 is still 3.13 against home-assistant's 3.14.
  dependencies = [ aiohttp ];

  meta = {
    description =
      "Home Assistant integration for Nest thermostats running No Longer Evil firmware";
    homepage = "https://github.com/patricktr/NoLongerEvil-HomeAssistant";
    license = lib.licenses.mit;
  };
}
