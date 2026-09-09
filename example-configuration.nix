# Example NixOS Configuration for Home Assistant Container
#
# This file demonstrates how to use the home-assistant-container flake
# in your NixOS configuration.
#
# Usage:
#   1. Add this flake to your flake.nix inputs
#   2. Import the nixosModule in your configuration
#   3. Customize the settings below for your setup

{ config, pkgs, inputs, ... }:

{
  # Import the Home Assistant Container module
  imports = [ inputs.home-assistant-container.nixosModules.default ];

  # No extra overlay is needed. The module takes its packages from this host's
  # own `pkgs`, and nixosModules.default appends the overlay it requires. Point
  # the flake at your nixpkgs (`inputs.nixpkgs.follows = "nixpkgs"`) so there is
  # a single instance in the closure.

  # ============================================================================
  # Basic Configuration
  # ============================================================================

  services.homeAssistantContainer = {
    # Enable the Home Assistant container service
    enable = true;

    # REQUIRED: Specify where Home Assistant stores its data
    # This directory will contain configuration.yaml, automations, custom components, etc.
    # Make sure this path exists and has appropriate permissions
    state-directory = "/var/lib/home-assistant";

    # REQUIRED: Your geographic location
    # Used for weather, sunrise/sunset times, and location-based automations
    position = {
      latitude = 47.6062; # Replace with your latitude
      longitude = -122.3321; # Replace with your longitude
    };

    # ============================================================================
    # Optional: General Configuration
    # ============================================================================

    # Display name for your Home Assistant instance
    # This appears in the UI and helps identify your home
    name = "My Smart Home"; # Default: "Home"

    # Trusted proxy networks for reverse proxy setups
    # Only these networks can send X-Forwarded-For headers
    # Default: ["127.0.0.0/16" "10.0.0.0/16" "::1"]
    trusted-proxies = [ "127.0.0.0/16" "10.0.0.0/16" "::1" ];

    # Prometheus metrics configuration
    # Set to null to disable metrics export
    prometheus = {
      requires-auth = false; # Set to true to require authentication
    };

    # ============================================================================
    # Port Configuration (Optional - defaults shown)
    # ============================================================================

    ports = {
      home-assistant = 8123; # Web interface
      node-red = 1880; # Node-Red editor
    };

    # ============================================================================
    # Voice Assistant Configuration
    # ============================================================================

    # Wake word model - what phrase triggers voice recognition
    # Available: hey_jarvis, ok_nabu, alexa, hey_mycroft, hey_rhasspy
    wake-word = "hey_jarvis";

    # NOTE: Speech-to-text (whisper.model / whisper.language) and
    # text-to-speech (piper.voice) options were removed 2026-07-10.
    # The local whisper/piper containers no longer ship with this module.
    # STT and TTS are now served by the k8s `wyoming` namespace
    # (stt.kube.sea.fudo.link / tts.kube.sea.fudo.link). Configure the
    # model and voice in your HA `stt:` / `tts:` integrations on the
    # cluster side instead.

    # ============================================================================
    # Optional: Additional Home Assistant Configuration
    # ============================================================================

    # Extra YAML configuration merged into configuration.yaml
    # This allows you to add any Home Assistant configuration not covered
    # by the module options
    extraConfig = ''
      # Automatically load automations and scripts from separate files
      automation: !include automations.yaml
      script: !include scripts.yaml
      scene: !include scenes.yaml

      # Example: Configure MQTT broker
      # mqtt:
      #   broker: 192.168.1.100
      #   port: 1883
      #   username: homeassistant
      #   password: !secret mqtt_password

      # Example: Configure notification service
      # notify:
      #   - platform: ntfy
      #     url: https://ntfy.sh
      #     topic: my-home-notifications

      # Example: Configure recorder to use MariaDB instead of SQLite
      # recorder:
      #   db_url: !secret db_url
      #   purge_keep_days: 7
      #   commit_interval: 30
    '';

    # Import additional configuration files from state-directory
    # These files should exist in /var/lib/home-assistant/
    extraImports = [
      "secrets.yaml" # Store sensitive data here
      # "customize.yaml"  # Entity customizations
      # "groups.yaml"     # Group definitions
    ];

    # ============================================================================
    # Optional: Custom Voice Commands
    # ============================================================================

    # Define simple voice command patterns
    # These will be saved to custom_sentences/en/custom_sentences.yaml
    customSimpleSentences = ''
      language: "en"
      intents:
        TurnOnTV:
          data:
            - sentences:
                - "turn on [the] TV"
                - "TV on"
                - "power on [the] television"

        SetThermostat:
          data:
            - sentences:
                - "set [the] temperature to {temperature}"
                - "make it {temperature} degrees"
    '';

    # Define custom voice intents with more complex handling
    # These will be saved to custom_sentences/en/intents.yaml
    customIntents = ''
      language: "en"
      intents:
        # Your custom intent handlers here
    '';

    # ============================================================================
    # Optional: Override Container Images
    # ============================================================================

    # Uncomment to use specific container image versions
    # images = {
    #   home-assistant = "ghcr.io/home-assistant/home-assistant:2024.1.0";
    #   node-red = "nodered/node-red:3.1.0";
    #   wake-word = "rhasspy/wyoming-openwakeword:latest";
    # };
  };

  # ============================================================================
  # Firewall Configuration
  # ============================================================================

  networking.firewall = {
    # Allow access to Home Assistant web interface
    allowedTCPPorts = [
      8123 # Home Assistant
      # 1880  # Uncomment to allow remote Node-Red access
    ];

    # Allow mDNS for automatic device discovery
    allowedUDPPorts = [
      5353 # mDNS/Zeroconf
    ];

    # Optional: Allow specific IP ranges (useful for mobile apps)
    # interfaces."eth0".allowedTCPPorts = [ 8123 ];
  };

  # ============================================================================
  # Optional: Automatic Backups
  # ============================================================================

  # Example using restic for automated backups
  # services.restic.backups.home-assistant = {
  #   paths = [ config.services.homeAssistantContainer.state-directory ];
  #   repository = "/mnt/backup/home-assistant";
  #   passwordFile = "/etc/nixos/secrets/restic-password";
  #   timerConfig = {
  #     OnCalendar = "daily";
  #   };
  # };

  # ============================================================================
  # Optional: Custom Systemd Service Overrides
  # ============================================================================

  # Ensure Home Assistant starts after network is fully up
  # systemd.services.arion-home-assistant = {
  #   after = [ "network-online.target" ];
  #   wants = [ "network-online.target" ];
  # };

  # ============================================================================
  # Secrets Management
  # ============================================================================

  # Create secrets.yaml file with restricted permissions
  # This example uses systemd-tmpfiles to create the file
  # In production, use proper secrets management (sops-nix, agenix, etc.)

  systemd.tmpfiles.rules = [
    # Create state directory if it doesn't exist
    "d ${config.services.homeAssistantContainer.state-directory} 0755 root root -"

    # Example: Create secrets.yaml with restricted permissions
    # "f ${config.services.homeAssistantContainer.state-directory}/secrets.yaml 0600 root root -"
  ];

  # ============================================================================
  # Notes and Tips
  # ============================================================================

  # 1. First Run:
  #    - After enabling, run: sudo nixos-rebuild switch
  #    - Access Home Assistant at: http://your-ip:8123
  #    - Follow the onboarding wizard to create your account
  #
  # 2. Adding Custom Components:
  #    - Place them in: /var/lib/home-assistant/custom_components/
  #    - Restart Home Assistant from the web UI
  #
  # 3. Voice Assistant Setup:
  #    - Go to Settings → Devices & Services → Add Integration
  #    - Search for "Wyoming Protocol"
  #    - Add Whisper (localhost:10300) for STT
  #    - Add Piper (localhost:10200) for TTS
  #    - Configure Assist pipeline in Settings → Voice assistants
  #
  # 4. Node-Red Integration:
  #    - Access Node-Red at: http://your-ip:1880
  #    - Install the Home Assistant palette
  #    - Configure the Home Assistant connection with your instance URL
  #
  # 5. Monitoring Logs:
  #    - systemctl status arion-home-assistant.service
  #    - journalctl -u arion-home-assistant.service -f
  #    - docker logs homeassistant -f
  #
  # 6. Updates:
  #    - Run: nix flake update
  #    - Then: sudo nixos-rebuild switch
  #    - Home Assistant tracks whichever nixpkgs this host is built from
}
