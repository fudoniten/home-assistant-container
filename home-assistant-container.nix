# Home Assistant Container NixOS Module
#
# This module provides a declarative way to run Home Assistant and related services
# in Docker containers managed by Arion (Nix's Docker Compose wrapper).
#
# The module deploys 3 containerized services:
# - home-assistant: Main Home Assistant hub
# - node-red: Visual automation flow editor
# - open-wake-word: Wake word detection for voice assistants
#
# Speech-to-text and text-to-speech are NOT included. The k8s `wyoming` namespace
# (stt.kube.sea.fudo.link / tts.kube.sea.fudo.link) serves STT/TTS over Tailscale
# for wormhole0's HA, and the same pattern applies to any host using this module.
# Configure your HA `stt:` and `tts:` integrations to point at the cluster FQDNs
# instead of running local Wyoming containers.
#
# Home Assistant runs in host network mode to enable device discovery protocols
# like mDNS, UPnP, and direct network access for IoT devices.

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.homeAssistantContainer;

  # Everything Home Assistant comes from the host's package set, which carries
  # this flake's overlay (`nixpkgs.overlays` is appended to `nixpkgs.pkgs`, so
  # it applies even when the host supplies its own nixpkgs instance).
  #
  # Bound here because `pkgs` is shadowed inside the Arion `image` function
  # below, and the two must not be mixed: home-assistant, the nixpkgs custom
  # components, the local components and the Lovelace modules all have to come
  # from one package set, or they are built against different Python scopes.
  #
  # This module used to instantiate its own nixpkgs-unstable carrying a
  # `python3 = python313` overlay. That overlay is a mass rebuild: `meson` is
  # `python3.pkgs.buildPythonApplication` and `nodejs` takes `python = python3`,
  # so nothing downstream of it matched cache.nixos.org and the consuming host
  # built the lot from source -- including nodejs, whose checkPhase runs the
  # whole `test-ci-js` suite. It did not even do what it claimed: nixpkgs'
  # home-assistant takes `python314Packages` directly and never reads the
  # top-level `python3`, so the aiounittest problem it was aimed at was never
  # addressed by it. See the note in flake.nix's `overlays` for why no
  # replacement workaround is needed on 26.05.
  hostPkgs = pkgs;

  # Priority constants for systemd tmpfiles
  # Lower numbers = higher priority (runs first)
  priorities = {
    tmpfiles = {
      host = 20; # Host-side directory creation
      container = 10; # Container-side file management
    };
  };

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
  homeAssistantPackages = with hostPkgs; [ zlib-ng ffmpeg go2rtc ];

  inherit (builtins) toJSON;

in {
  # ============================================================================
  # Module Options
  # ============================================================================

  options.services.homeAssistantContainer = with types; {
    enable = mkEnableOption "Enable Home Assistant running in a container.";

    # Container image configuration for Docker-based services
    # The home-assistant container is built from nixpkgs (via Arion's nixos mode)
    # and does not use a Docker image — its version tracks pkgs.home-assistant.
    #
    # Whisper and Piper were removed (2026-07-10): the k8s `wyoming` namespace
    # (stt.kube.sea.fudo.link, tts.kube.sea.fudo.link) now serves STT/TTS
    # over Tailscale for wormhole0's HA, and the local containers were
    # consuming resources and generating journal noise without being on
    # the audio path. Configure your HA `stt:` and `tts:` integrations to
    # point at the cluster FQDNs instead.
    images = genAttrs [ "node-red" "open-wake-word" ] (imgType:
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

    # NOTE: the `nest` option (Google Nest client-id/client-secret/project-id,
    # written into configuration.yaml) was removed. The thermostat it existed
    # for is too old for Google's SDM API, and is driven by the `nolongerevil`
    # custom component instead -- see `customComponents` below.
    #
    # It had never worked in any case: the submodule was built from a bare
    # attrset of options rather than `{ options = ...; }`, so any value at all
    # threw "there are no options defined in `nest'". Nothing set it, so
    # nothing noticed. `prometheus` and `position` show the correct form.

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

    # Display name for the Home Assistant instance
    # This appears in the UI and can help identify your home
    name = mkOption {
      type = str;
      description = "Display name for your Home Assistant instance.";
      default = "Home";
      example = "My Smart Home";
    };

    # Network configuration
    # Controls proxy and network security settings

    # Trusted proxy networks for reverse proxy setups
    # These networks can send X-Forwarded-For headers that Home Assistant will trust
    # Default includes localhost and typical Docker/home network ranges
    trusted-proxies = mkOption {
      type = listOf str;
      description = "List of trusted proxy networks in CIDR notation.";
      default = [ "127.0.0.0/16" "10.0.0.0/16" "::1" ];
      example = [ "127.0.0.1" "192.168.1.100" ];
    };

    # Prometheus metrics configuration
    prometheus = mkOption {
      type = nullOr (submodule {
        options = {
          requires-auth = mkOption {
            type = bool;
            description =
              "Whether Prometheus metrics endpoint requires authentication.";
            default = false;
          };
        };
      });
      description =
        "Prometheus metrics export configuration. Set to null to disable.";
      default = { };
    };

    # Unit configuration
    # Controls temperature and measurement units in the UI

    # Temperature unit for display
    temperature-unit = mkOption {
      type = enum [ "C" "F" ];
      description = "Temperature unit: C (Celsius) or F (Fahrenheit).";
      default = "C";
      example = "F";
    };

    # Measurement unit system
    unit-system = mkOption {
      type = enum [ "metric" "imperial" "us_customary" ];
      description =
        "Unit system for distances, weights, and volumes. metric = km/kg/L, imperial = mi/lb/gal (UK), us_customary = mi/lb/gal (US).";
      default = "metric";
      example = "imperial";
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

    # NOTE: Speech-to-text (whisper.model / whisper.language) and
    # text-to-speech (piper.voice) options were removed 2026-07-10.
    # The local whisper/piper containers no longer ship with this module —
    # STT and TTS are now served by the k8s `wyoming` namespace
    # (stt.kube.sea.fudo.link / tts.kube.sea.fudo.link). Configure the
    # model and voice in your HA `stt:` / `tts:` integrations on the
    # cluster side instead.

    # Geographic position configuration
    # Used for:
    # - Weather forecasts
    # - Sunrise/sunset calculations
    # - Location-based automations
    # - Timezone determination
    position = let
      posOpts = {
        options = {
          latitude = mkOption {
            type = float;
            description = "Latitude in degrees. Valid range: -90 to 90.";
            example = 47.6062;
          };
          longitude = mkOption {
            type = float;
            description = "Longitude in degrees. Valid range: -180 to 180.";
            example = -122.3321;
          };
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
    # Input validation assertions
    assertions = [
      {
        assertion = cfg.state-directory != "";
        message =
          "services.homeAssistantContainer.state-directory must be set to a valid path";
      }
      {
        assertion = !isNull cfg.position
          -> (cfg.position.latitude >= -90.0 && cfg.position.latitude <= 90.0);
        message =
          "services.homeAssistantContainer.position.latitude must be between -90 and 90 degrees";
      }
      {
        assertion = !isNull cfg.position -> (cfg.position.longitude >= -180.0
          && cfg.position.longitude <= 180.0);
        message =
          "services.homeAssistantContainer.position.longitude must be between -180 and 180 degrees";
      }
      # Container image assertions - users must explicitly specify all images
      # Note: home-assistant is excluded; it is built from pkgs.home-assistant via Arion's nixos mode
      {
        assertion = cfg.images.node-red != "";
        message =
          "services.homeAssistantContainer.images.node-red must be explicitly set (e.g., 'nodered/node-red:latest')";
      }
      {
        assertion = cfg.images.open-wake-word != "";
        message =
          "services.homeAssistantContainer.images.open-wake-word must be explicitly set (e.g., 'rhasspy/wyoming-openwakeword:latest')";
      }
    ];

    # Create required directories for container state storage
    # Each service gets its own subdirectory to isolate data
    # These directories are created on the host and mounted into containers
    systemd = {
      tmpfiles.settings = {
        "${toString priorities.tmpfiles.host}-home-assistant" = let
          mkRule = subdir: {
            d = {
              user = "root";
              group = "root";
              mode = "0700";
            };
          };
          subdirs = [ "config" "node-red" "open-wake-word" ];
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
              depends_on = [ "node-red" "open-wake-word" ];

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
                  services.home-assistant = {
                    path = homeAssistantPackages;
                    environment.LD_LIBRARY_PATH =
                      makeLibraryPath homeAssistantPackages;
                  };

                  # Create required files and symlinks inside the container
                  tmpfiles.settings = {
                    "${toString priorities.tmpfiles.container}-home-assistant" =
                      {
                        # Create empty YAML files if they don't exist
                        # Home Assistant will populate these through the UI
                        "/var/lib/home-assistant/automations.yaml".f = {
                          user = "hass";
                          group = "hass";
                          mode = "0644"; # Read/write for owner, read for group
                        };
                        "/var/lib/home-assistant/scenes.yaml".f = {
                          user = "hass";
                          group = "hass";
                          mode = "0644"; # Read/write for owner, read for group
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
                  configDir = "/var/lib/home-assistant";
                  # Allow UI-based Lovelace dashboard editing
                  lovelaceConfigWritable = true;

                  # Plain home-assistant from the host's package set: the same
                  # derivation cache.nixos.org has, so it substitutes. The
                  # `packageOverrides` that used to sit here (un-disabling
                  # aiounittest for python314) is no longer needed on 26.05 --
                  # see the note in flake.nix's overlays for what was checked.
                  package = hostPkgs.home-assistant;

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
                    "jellyfin"
                    "kraken"
                    "marytts"
                    "mcp"
                    "mcp_server"
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
                    "open_router"
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
                    "wyoming" # Wyoming Protocol for voice assistants
                  ];

                  # Additional Python packages required by components
                  # These are dependencies not automatically detected or not in nixpkgs
                  extraPackages = pyPkgs:
                    with pyPkgs; [
                      aiohttp-fast-zlib # Faster compression for web requests
                      aiohomekit # HomeKit controller integration dependency
                      gtts # Google Text-to-Speech
                      grpcio # gRPC support for Nest/Google integrations
                      pyforked-daapd # DAAP/iTunes library integration
                      pynws # National Weather Service API
                      pyPkgs."grpcio-status" # gRPC status codes
                      # Web proxy support. This was a hand-rolled 0.0.7
                      # buildPythonPackage here, with its own PyPI hash to keep
                      # current; nixpkgs carries it in home-assistant's own
                      # Python scope now (defaultOverrides -> 0.0.8).
                      hass-web-proxy-lib
                      pyatv # Apple TV integration
                    ];

                  # Custom Lovelace UI cards from nixpkgs
                  # These enhance the Home Assistant frontend with additional card types
                  customLovelaceModules =
                    with hostPkgs.home-assistant-custom-lovelace-modules; [
                      bubble-card # Modern bubble-style cards
                      button-card # Highly customizable buttons
                      card-mod # CSS styling for cards
                      mini-graph-card # Compact history graphs
                      mini-media-player # Compact media player controls
                      multiple-entity-row # Multiple entities per row
                      mushroom # Minimalist card theme
                      weather-card # Animated weather cards
                    ];

                  # Custom components (third-party integrations)
                  customComponents =
                    # Both sets come from hostPkgs, the same package set as
                    # `package` above, so the components and the
                    # home-assistant running them share one Python scope --
                    # `home-assistant-custom-components` is scoped off
                    # `home-assistant.python3Packages`, so taking the two from
                    # different nixpkgs instances (which is what this module
                    # used to do) means building components against a Python
                    # set that is not the one loading them.
                    (with hostPkgs.home-assistant-custom-components; [
                      frigate # NVR with object detection
                      ntfy # Simple push notifications
                      prometheus_sensor # Custom Prometheus metrics
                    ]) ++ (with hostPkgs.home-assistant-local-components; [
                      nodered # Node-Red integration
                      nolongerevil # No Longer Evil thermostat (cloud API)
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
                    mobile_app = { }; # Mobile app companion support
                    cloud = { }; # Nabu Casa cloud services
                    history = { }; # Historical data tracking
                    energy = { }; # Energy monitoring dashboard
                    recorder = { }; # Database recording
                    default_config = { }; # Load default configuration

                    # HTTP server configuration
                    http = {
                      server_host = [ "0.0.0.0" ]; # Listen on all interfaces
                      server_port = 8123;
                      use_x_forwarded_for = true; # Trust proxy headers
                      # Trusted proxy networks (for reverse proxy setups)
                      # Configurable via trusted-proxies option
                      trusted_proxies = cfg.trusted-proxies;
                    };

                    # General Home Assistant settings
                    homeassistant = {
                      name = cfg.name; # Configurable display name
                      temperature_unit =
                        cfg.temperature-unit; # Configurable temperature unit
                      time_zone = timezone; # From system config
                      unit_system = cfg.unit-system; # Configurable unit system
                    } // (optionalAttrs (!isNull cfg.position) {
                      # Geographic coordinates (if configured)
                      latitude = cfg.position.latitude;
                      longitude = cfg.position.longitude;
                    });

                    # Prometheus metrics export (if configured)
                    prometheus = mkIf (!isNull cfg.prometheus) {
                      namespace = "hass";
                      requires_auth = cfg.prometheus.requires-auth;
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
            volumes =
              [ "node-red-data:/data" ]; # Named volume for flows and settings
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

          # NOTE: local whisper and piper services were removed 2026-07-10.
          # STT and TTS are now served by the k8s `wyoming` namespace
          # (stt.kube.sea.fudo.link / tts.kube.sea.fudo.link). The local
          # containers were not on the audio path; they consumed resources
          # and generated journal noise. Configure your HA `stt:` and `tts:`
          # integrations to point at the cluster FQDNs over Tailscale.
        };
      };
    in { imports = [ image ]; };
  };
}
