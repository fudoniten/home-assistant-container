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
  imports = [
    inputs.home-assistant-container.nixosModules.default
  ];

  # Required: Add nixpkgs-unstable overlay for Home Assistant packages
  nixpkgs.overlays = [
    (final: prev: {
      pkgsUnstable = import inputs.nixpkgs-unstable {
        system = prev.system;
        config.allowUnfree = true;
      };
    })
  ];

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
      latitude = 47.6062;    # Replace with your latitude
      longitude = -122.3321; # Replace with your longitude
    };

    # ============================================================================
    # Port Configuration (Optional - defaults shown)
    # ============================================================================

    ports = {
      home-assistant = 8123;  # Web interface
      node-red = 1880;        # Node-Red editor
      piper = 10200;          # Text-to-speech service
      whisper = 10300;        # Speech-to-text service
      wake-word = 10400;      # Wake word detection
    };

    # ============================================================================
    # Voice Assistant Configuration
    # ============================================================================

    # Wake word model - what phrase triggers voice recognition
    # Available: hey_jarvis, ok_nabu, alexa, hey_mycroft, hey_rhasspy
    wake-word = "hey_jarvis";

    # Speech-to-text (Whisper) model
    # Options: tiny-int8 (fastest), base, small, medium, large (most accurate)
    # Larger models require more CPU/memory but are more accurate
    whisper.model = "tiny-int8";

    # Text-to-speech (Piper) voice
    # Browse available voices at: https://rhasspy.github.io/piper-samples/
    piper.voice = "en-gb-southern_english_female-low";

    # ============================================================================
    # Optional: Nest Thermostat Integration
    # ============================================================================

    # Uncomment and fill in your Nest credentials if you use Nest devices
    # Get these from: https://console.cloud.google.com/
    # nest = {
    #   project-id = "your-nest-project-id";
    #   client-id = "your-oauth-client-id";
    #   client-secret = "your-oauth-client-secret";
    # };

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
      "secrets.yaml"      # Store sensitive data here
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
    #   piper = "rhasspy/wyoming-piper:latest";
    #   whisper = "rhasspy/wyoming-whisper:latest";
    #   wake-word = "rhasspy/wyoming-openwakeword:latest";
    # };
  };

  # ============================================================================
  # Firewall Configuration
  # ============================================================================

  networking.firewall = {
    # Allow access to Home Assistant web interface
    allowedTCPPorts = [
      8123  # Home Assistant
      # 1880  # Uncomment to allow remote Node-Red access
    ];

    # Allow mDNS for automatic device discovery
    allowedUDPPorts = [
      5353  # mDNS/Zeroconf
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
  #    - Home Assistant will use the latest images from nixpkgs-unstable
}
