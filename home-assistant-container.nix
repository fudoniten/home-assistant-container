# Home Assistant Container NixOS Module
#
# This module provides a declarative way to run Home Assistant and related services
# in Docker containers managed by Arion (Nix's Docker Compose wrapper).
#
# The module deploys 5 containerized services:
# - home-assistant: Main Home Assistant hub
# - node-red: Visual automation flow editor
# - open-wake-word: Wake word detection for voice assistants
# - whisper: Speech-to-text using OpenAI Whisper
# - piper: Text-to-speech using Piper voices
#
# Home Assistant runs in host network mode to enable device discovery protocols
# like mDNS, UPnP, and direct network access for IoT devices.

{ inputs, ... }:

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.homeAssistantContainer;

  # Use system timezone for all containers
  timezone = config.time.timeZone;

  # Helper function to flatten nested attribute sets for environment.etc
  # Used to create file paths for custom sentence configurations
  flatMapAttrs' = f: attrs:
    listToAttrs (concatLists
      (mapAttrsToList (a: subattrs: mapAttrsToList (b: val: f a b val) subattrs)
        attrs));

  # YAML type for configuration options
  yamlType = (pkgs.formats.yaml { }).type;

  # System packages required by Home Assistant for native library support
  homeAssistantPackages = with pkgs; [ zlib-ng ];

  inherit (builtins) toJSON;

in {
  # ============================================================================
  # Module Options
  # ============================================================================

  options.services.homeAssistantContainer = with types; {
    enable = mkEnableOption "Enable Home Assistant running in a container.";

    # Container image overrides
    # By default, images come from nixpkgs, but these options allow specifying
    # custom image references (useful for testing or pinning versions)
    images = genAttrs [
      "home-assistant"
      "node-red"
      "open-wake-word"
      "whisper"
      "piper"
    ] (imgType:
      mkOption {
        type = str;
        description = "${imgType} container image.";
      });

    # Network port configuration
    # These ports are exposed on the host machine for accessing services
    ports = {
      home-assistant = mkOption {
        type = port;
        description =
          "Port on which to listen for connections to Home Assistant.";
        default = 8123;
      };

      node-red = mkOption {
        type = port;
        description = "Port on which to listen for connections to Node Red.";
        default = 1880;
      };
    };

    # Google Nest integration credentials
    # Required if you want to control Nest thermostats and other Nest devices
    # Credentials are obtained from Google Cloud Console
    nest = mkOption {
      type = let
        nestOpts = {
          client-id = mkOption { type = str; };
          client-secret = mkOption { type = str; };
          project-id = mkOption { type = str; };
        };
      in nullOr (submodule nestOpts);
      default = null;
    };

    # Additional Home Assistant configuration
    # This YAML-compatible configuration is merged into configuration.yaml
    # Use this to add any Home Assistant settings not covered by module options
    extraConfig = mkOption {
      type = yamlType;
      description = "Extra configuration options in YAML-compatible format.";
      default = { };
    };

    # Additional configuration file imports
    # Files must exist in the state-directory and will be imported into
    # Home Assistant's configuration.yaml using !include directives
    extraImports = mkOption {
      type = attrsOf path;
      description = "Map of config name to import file.";
      default = { };
    };

    # Simple custom voice command definitions
    # Define voice commands that map directly to intents without complex logic
    # These are saved to custom_sentences/en/custom_sentences.yaml
    customSimpleSentences = mkOption {
      type = attrsOf yamlType;
      description = "Map of sentence name to intent config.";
      default = { };
      example = { YearOfVoice = [ "how is this year going?" ]; };
    };

    # Advanced custom voice command patterns
    # Define complex sentence patterns with variables and templates
    # These are saved as separate YAML files in custom_sentences/<lang>/
    # String type allows Jinja2 template syntax
    customSentences = mkOption {
      type = attrsOf (attrsOf str);
      description =
        "Map of language to sentence filename to sentence JSON configuration.";
      default = { };
      example = {
        en = {
          MopidyPlaySong = ''{ "data": [ "play {song} [by] {artist}" ] }'';
        };
      };
    };

    # Custom intent handlers
    # Define what actions to take when voice commands are recognized
    # Supports Home Assistant script syntax with variables and actions
    customIntents = mkOption {
      type = attrsOf yamlType;
      description = "Map of intent name to JSON configuration.";
      default = { };
      example = {
        MopidyPlaySong = {
          action = [
            {
              variables = {
                song = "{{ trigger.slots.song }}";
                artist = "{{ trigger.slots.artist | default('') }}";
              };
            }
            {
              action = "script.mopidy_play_search";
              data.query = "{{ song }} {{ artist }}";
            }
          ];
          speech.text = "Okay, playing the song!";
        };
      };
    };

    # Storage location for Home Assistant data
    # This directory will contain:
    # - configuration.yaml (auto-generated)
    # - automations.yaml, scripts.yaml, etc.
    # - custom_components/ (user-installed integrations)
    # - .storage/ (internal Home Assistant data)
    # Must be specified and should be persistent across reboots
    state-directory = mkOption {
      type = str;
      description = "Path at which to store Home Assistant state data.";
    };

    # Voice assistant configuration
    # These options configure the Wyoming Protocol voice services

    # Wake word model for voice activation
    # Common models: hey_jarvis, ok_nabu, alexa, hey_mycroft, hey_rhasspy
    # The model will be preloaded for faster detection
    wake-word = mkOption {
      type = str;
      description = "Model to use for Home Assistant satellites. Must exist!";
      default = "hey_jarvis";
    };

    # Speech-to-text (Whisper) model selection
    # Trade-off between speed and accuracy:
    # - tiny-int8: Fastest, lowest resource usage, good for basic commands
    # - base, small: Balanced performance
    # - medium, large: Most accurate, requires more CPU/memory
    whisper.model = mkOption {
      type = str;
      description = "Voice-to-text model to use for Whisper.";
      default = "tiny-int8";
    };

    # Text-to-speech (Piper) voice selection
    # Browse available voices at: https://rhasspy.github.io/piper-samples/
    # Format: <language>-<region>-<name>-<quality>
    # Quality levels: low (fastest), medium, high (best quality)
    piper.voice = mkOption {
      type = str;
      description = "Voice to use when generating audio from text.";
      default = "en-gb-southern_english_female-low";
    };

    # Geographic position configuration
    # Used for:
    # - Weather forecasts
    # - Sunrise/sunset calculations
    # - Location-based automations
    # - Timezone determination
    position = let
      posOpts = {
        options = {
          latitude = mkOption { type = float; };
          longitude = mkOption { type = float; };
        };
      };
    in mkOption {
      type = nullOr (submodule posOpts);
      description =
        "Position of the home running this Home Assistant instance.";
      default = null;
    };
  };

  # ============================================================================
  # Module Configuration
  # ============================================================================

  config = mkIf cfg.enable {
    # Create required directories for container state storage
    # Each service gets its own subdirectory to isolate data
    # These directories are created on the host and mounted into containers
    systemd = {
      tmpfiles.settings = {
        "20-home-assistant" = let
          mkRule = subdir: {
            d = {
              user = "root";
              group = "root";
              mode = "0700";
            };
          };
          subdirs = [ "config" "node-red" "open-wake-word" "whisper" "piper" ];
        in genAttrs (map (subdir: "${cfg.state-directory}/${subdir}") subdirs)
        mkRule;
      };
    };

    # Arion project configuration
    # Arion is a Nix wrapper around Docker Compose that enables declarative
    # container definitions with the full power of Nix for building images
    virtualisation.arion.projects.home-assistant.settings = let
      image = { pkgs, config, ... }: {
        project.name = "home-assistant";
        docker-compose.volumes = { node-red-data = { }; };
        services = {
          # ====================================================================
          # Home Assistant Main Service
          # ====================================================================
          # This service runs the full Home Assistant application in a
          # NixOS container (not just a Docker image), allowing us to use
          # Nix to declaratively configure Home Assistant itself
          home-assistant = {
            service = {
              restart = "always";
              volumes =
                [ "${cfg.state-directory}/config:/var/lib/home-assistant" ];
              ports = [ "${toString cfg.ports.home-assistant}:8123" ];
              depends_on = [ "node-red" "open-wake-word" "whisper" "piper" ];

              # Host network mode is REQUIRED for Home Assistant to function properly
              # Reasons:
              # 1. mDNS/Zeroconf device discovery (Chromecast, smart TVs, etc.)
              # 2. UPnP/DLNA protocol support
              # 3. Direct network access for ESPHome and other local integrations
              # 4. Multicast protocols used by many IoT devices
              #
              # Security Note: Host mode removes network isolation. Ensure your
              # NixOS firewall is properly configured to protect Home Assistant.
              network_mode = "host";
            };
            nixos = {
              useSystemd = true;
              configuration = {
                imports = [
                  ({ ... }: {
                    services.home-assistant.config = cfg.extraConfig;
                  })
                ];
                boot.tmp.useTmpfs = true;
                system.nssModules = mkForce [ ];
                systemd = {
                  # Add native library paths for Home Assistant dependencies
                  services.home-assistant.environment.LD_LIBRARY_PATH =
                    makeLibraryPath homeAssistantPackages;

                  # Create required files and symlinks inside the container
                  tmpfiles.settings = {
                    "10-home-assistant" = {
                      # Create empty YAML files if they don't exist
                      # Home Assistant will populate these through the UI
                      "/var/lib/home-assistant/automations.yaml".f = {
                        user = "hass";
                        group = "hass";
                        mode = "0644";  # Read/write for owner, read for group
                      };
                      "/var/lib/home-assistant/scenes.yaml".f = {
                        user = "hass";
                        group = "hass";
                        mode = "0644";  # Read/write for owner, read for group
                      };
                      # Symlink custom sentence files from /etc to config directory
                      # This makes Nix-managed sentence configs available to Home Assistant
                      "/var/lib/home-assistant/custom_sentences"."L+" = {
                        argument = "/etc/home-assistant/custom_sentences";
                      };
                    };
                  };
                };
                environment = {
                  systemPackages = homeAssistantPackages;

                  # Map custom intent configurations to /etc for container access
                  etc = flatMapAttrs' (lang: name: intentCfg:
                    nameValuePair
                    "home-assistant/custom_sentences/${lang}/${name}.yaml"
                    intentCfg) cfg.customIntents;
                };

                # Home Assistant NixOS service configuration
                services.home-assistant = {
                  enable = true;
                  # Use Home Assistant from nixpkgs-unstable for latest features
                  package = pkgs.pkgsUnstable.home-assistant;
                  configDir = "/var/lib/home-assistant";
                  # Allow UI-based Lovelace dashboard editing
                  lovelaceConfigWritable = true;

                  # Built-in Home Assistant components to enable
                  # These are the official integrations that ship with Home Assistant
                  extraComponents = [
                    "default_config"
                    "met"
                    "esphome"
                    "accuweather"
                    "adguard"
                    "androidtv"
                    "androidtv_remote"
                    "api"
                    "august"
                    "binary_sensor"
                    "brother"
                    "calendar"
                    "cast"
                    "coinbase"
                    "energy"
                    "google"
                    "google_assistant"
                    "google_generative_ai_conversation"
                    "history"
                    "ipp"
                    "kraken"
                    "marytts"
                    "media_player"
                    "media_source"
                    "mobile_app"
                    "mpd"
                    "mqtt"
                    "minecraft_server"
                    "music_assistant"
                    "nest"
                    "nmap_tracker"
                    "ollama"
                    "openai_conversation"
                    "otbr"
                    "pocketcasts"
                    "prometheus"
                    "proximity"
                    "radio_browser"
                    "recorder"
                    "samsungtv"
                    "spotify"
                    "sun"
                    "synology_dsm"
                    "tile"
                    "upnp"
                    "wyoming"  # Wyoming Protocol for voice assistants
                  ];

                  # Additional Python packages required by components
                  # These are dependencies not automatically detected or not in nixpkgs
                  extraPackages = pyPkgs:
                    let
                      # Custom build of hass-web-proxy-lib (not in nixpkgs)
                      hass-web-proxy = pyPkgs.buildPythonPackage rec {
                        pname = "hass-web-proxy-lib";
                        version = "0.0.7";
                        pyproject = true;

                        src = pyPkgs.fetchPypi {
                          pname = "hass_web_proxy_lib";
                          inherit version;
                          sha256 =
                            "sha256-bhz71tNOpZ+4tSlndS+UbC3w2WW5+dAMtpk7TnnFpuQ=";
                        };

                        propagatedBuildInputs = with pyPkgs; [ aiohttp ];
                        dependencies = with pyPkgs; [ aiohttp homeassistant ];
                        doCheck = false;
                        build-system = with pyPkgs; [
                          poetry-core
                          setuptools
                          wheel
                        ];
                        pythonImportsCheck = [ "hass_web_proxy_lib" ];
                      };
                    in with pyPkgs; [
                      aiohttp-fast-zlib  # Faster compression for web requests
                      gtts               # Google Text-to-Speech
                      grpcio             # gRPC support for Nest/Google integrations
                      pyforked-daapd     # DAAP/iTunes library integration
                      pynws              # National Weather Service API
                      pyPkgs."grpcio-status"  # gRPC status codes
                      hass-web-proxy     # Web proxy support (custom build)
                      pyatv              # Apple TV integration
                    ];

                  # Custom Lovelace UI cards from nixpkgs
                  # These enhance the Home Assistant frontend with additional card types
                  customLovelaceModules =
                    with pkgs.home-assistant-custom-lovelace-modules; [
                      bubble-card          # Modern bubble-style cards
                      button-card          # Highly customizable buttons
                      card-mod             # CSS styling for cards
                      mini-graph-card      # Compact history graphs
                      mini-media-player    # Compact media player controls
                      multiple-entity-row  # Multiple entities per row
                      mushroom             # Minimalist card theme
                      weather-card         # Animated weather cards
                    ];

                  # Custom components (third-party integrations)
                  customComponents =
                    # Components from nixpkgs
                    (with pkgs.home-assistant-custom-components; [
                      frigate            # NVR with object detection
                      ntfy               # Simple push notifications
                      prometheus_sensor  # Custom Prometheus metrics
                    ]) ++
                    # Components built by this flake
                    (with pkgs.home-assistant-local-components; [
                      nodered            # Node-Red integration
                      openai_tts         # OpenAI text-to-speech
                    ]);

                  # Home Assistant configuration.yaml generation
                  # This is merged with extraConfig to create the final configuration
                  config = {
                    # Automation configuration
                    "automation ui" = "!include automations.yaml";
                    "automation manual" = [ ];
                    # Scene configuration
                    "scene ui" = "!include scenes.yaml";
                    "scene manual" = [ ];

                    # Core integrations
                    mobile_app = { };        # Mobile app companion support
                    cloud = { };             # Nabu Casa cloud services
                    history = { };           # Historical data tracking
                    energy = { };            # Energy monitoring dashboard
                    recorder = { };          # Database recording
                    default_config = { };    # Load default configuration

                    # HTTP server configuration
                    http = {
                      server_host = [ "0.0.0.0" ];  # Listen on all interfaces
                      server_port = 8123;
                      use_x_forwarded_for = true;   # Trust proxy headers
                      # Trusted proxy networks (for reverse proxy setups)
                      # localhost and private network ranges
                      trusted_proxies = [ "127.0.0.0/16" "10.0.0.0/8" "::1" ];
                    };

                    # General Home Assistant settings
                    homeassistant = {
                      name = "Seattle";              # Display name (TODO: make configurable)
                      temperature_unit = "C";        # Celsius
                      time_zone = timezone;          # From system config
                      unit_system = "metric";        # Metric units (km, kg, etc.)
                    } // (optionalAttrs (!isNull cfg.position) {
                      # Geographic coordinates (if configured)
                      latitude = cfg.position.latitude;
                      longitude = cfg.position.longitude;
                    });

                    # Google Nest integration (if configured)
                    nest = mkIf (!isNull cfg.nest) {
                      client_id = cfg.nest.client-id;
                      client_secret = cfg.nest.client-secret;
                      project_id = cfg.nest.project-id;
                    };

                    # Prometheus metrics export
                    # WARNING: No authentication required - only enable on trusted networks
                    prometheus = {
                      namespace = "hass";
                      requires_auth = false;
                    };

                    # Voice conversation configuration
                    conversation.intents = cfg.customSentences;

                    # Custom voice intent handlers
                    # Scripts that run when voice commands are recognized
                    intent_script = let
                      scriptConfig = pkgs.writeText "intent_scripts.yaml"
                        (toJSON cfg.customIntents);
                    in "!include ${scriptConfig}";

                  # Merge extra configuration file imports
                  } // (mapAttrs (_: filename: "!include ${filename}")
                    cfg.extraImports);
                };
              };

            };
          };

          # ====================================================================
          # Node-Red Service
          # ====================================================================
          # Visual flow-based automation and integration tool
          # Web UI accessible at configured port (default: 1880)
          node-red.service = {
            image = cfg.images.node-red;
            restart = "always";
            volumes = [ "node-red-data:/data" ];  # Named volume for flows and settings
            environment.TZ = timezone;
            ports = [ "${toString cfg.ports.node-red}:1880" ];
          };

          # ====================================================================
          # Open-Wake-Word Service
          # ====================================================================
          # Listens for wake words to activate voice assistant
          # Uses Wyoming Protocol for communication with Home Assistant
          # Models are preloaded for faster detection (avoid cold-start delay)
          open-wake-word.service = {
            image = cfg.images.open-wake-word;
            restart = "always";
            volumes = [ "${cfg.state-directory}/open-wake-word:/data" ];
            environment.TZ = timezone;
            # Preload configured wake word model into memory
            command = "--preload-model '${cfg.wake-word}'";
            # Exposes both TCP and UDP for flexibility
            ports = [ "10400:10400/tcp" "10400:10400/udp" ];
          };

          # ====================================================================
          # Whisper Service (Speech-to-Text)
          # ====================================================================
          # OpenAI's Whisper for converting spoken commands to text
          # Uses faster-whisper implementation for better performance
          # Language is hardcoded to English (TODO: make configurable)
          whisper.service = {
            image = cfg.images.whisper;
            restart = "always";
            volumes = [ "${cfg.state-directory}/whisper:/data" ];
            environment.TZ = timezone;
            entrypoint = "python3";
            command = concatStringsSep " " [
              "-m wyoming_faster_whisper"
              "--uri tcp://0.0.0.0:10300"
              "--model ${cfg.whisper.model}"  # Configurable model size
              "--beam-size 1"                 # Faster decoding (less accurate)
              "--language en"                 # English only (TODO: make configurable)
              "--data-dir /data"              # Model storage location
              "--download-dir /data"          # Model download location
            ];
            ports = [ "10300:10300" ];
          };

          # ====================================================================
          # Piper Service (Text-to-Speech)
          # ====================================================================
          # Fast, local text-to-speech using neural voices
          # Much faster than cloud TTS services and works offline
          piper.service = {
            image = cfg.images.piper;
            restart = "always";
            volumes = [ "${cfg.state-directory}/piper:/data" ];
            environment.TZ = timezone;
            # Voice is configured via options (see piper.voice option)
            command = "--voice ${cfg.piper.voice}";
            ports = [ "10200:10200" ];
          };
        };
      };
    in { imports = [ image ]; };
  };
}
