{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.homeAssistantContainer;

  hostname = config.instance.hostname;

in {
  options.services.homeAssistantContainer = with types; {
    enable = mkEnableOption "Enable Home Assistant running in a container.";

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

    # mqtt = {
    #   broker = mkOption {
    #     type = str;
    #     description = "URL to the local MQTT broker.";
    #   };

    #   username = mkOption {
    #     type = str;
    #     description = "Home Assistant MQTT username.";
    #   };

    #   password = mkOption {
    #     type = str;
    #     description = "Home Assistant MQTT password.";
    #   };
    # };

    state-directory = mkOption {
      type = str;
      description = "Path at which to store Home Assistant state data.";
    };

    wake-word = mkOption {
      type = str;
      description = "Model to use for Home Assistant satellites. Must exist!";
      default = "hey_jarvis";
    };

    whisper.model = mkOption {
      type = str;
      description = "Voice-to-text model to use for Whisper.";
      default = "tiny-int8";
    };

    piper.voice = mkOption {
      type = str;
      description = "Voice to use when generating audio from text.";
      default = "en-gb-southern_english_female-low";
    };
  };

  config = {
    systemd.tmpfiles = {
      "20-home-assistant" = let
        mkRule = subdir:
          dir {
            type = "d";
            user = "root";
            group = "root";
            mode = "0700";
          };
        subdirs = [ "config" "node-red" "open-wake-word" "whisper" "piper" ];
      in genAttrs (map (subdir: "${cfg.state-directory}/${subdir}") subdirs)
      mkRule;
    };

    virtualisation.arion.projects.home-assistant.settings = let
      image = { config, pkgs, ... }: {
        project.name = "home-assistant";
        networks = {
          external_network.internal = false;
          internal_network.internal = true;
        };
        services = {
          home-assistant = {
            service = {
              restart = "always";
              networks = [ "internal_network" "external_network" ];
              volumes = [
                "${cfg.state-directory}/config:${config.services.home-assistant.configDir}"
              ];
              ports = [ "${toString cfg.ports.home-assistant}:8123" ];
              depends_on = [ "node-red" "open-wake-word" "whisper" "piper" ];
            };
            nixos = {
              useSystemd = true;
              configuration = {
                boot.tmp.useTmpfs = true;
                system.nssModules = mkForce [ ];
                services.home-assistant = {
                  enable = true;
                  lovelaceConfigWritable = true;
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
                    "google"
                    "google_assistant"
                    "google_calendar"
                    "google_generative_ai_conversation"
                    "ipp"
                    "kraken"
                    "media_player"
                    "media_source"
                    "mobile_app"
                    "mqtt"
                    "minecraft_server"
                    "nest"
                    "nmap_tracker"
                    "openai_conversation"
                    "pocketcasts"
                    "prometheus"
                    "proximity"
                    "radio_browser"
                    "samsungtv"
                    "sun"
                    "synology_dsm"
                    "tile"
                    "upnp"
                    "wyoming"
                  ];
                  customLovelaceModules =
                    with pkgs.home-assistant.customLovelaceModules; [
                      android-tv-card
                      button-card
                      mini-graph-card
                      mini-media-player
                      multiple-entity-row
                      mushroom
                    ];
                  customComponents =
                    with pkgs.home-assistant.customComponents; [
                      frigate
                      ntfy
                      prometheus_sensor
                    ];
                  config = {
                    # components = {
                    #   mqtt = {
                    #     inherit (cfg.mqtt) broker password username;
                    #     discovery = true;
                    #   };
                    # };
                    http = {
                      server_host = [ "0.0.0.0" ];
                      server_port = [ "8123" ];
                      use_x_forwarded_for = true;
                    };
                    homeassistant = {
                      name = "Seattle";
                      temperature_unit = "C";
                      time_zone = config.time.timeZone;
                      unit_system = "metric";
                      latitude = cfg.latitude; # "47.52694";
                      longitude = cfg.longitude; # "-122.16804";
                    };
                    nest = mkIf (!isNull cfg.nest) {
                      client_id = cfg.nest.client_id;
                      client_secret = cfg.nest.client_secret;
                      project_id = cfg.nest.project_id;
                    };
                    prometheus = {
                      namespace = "hass";
                      requires_auth = false;
                    };
                  };
                };
              };

            };
          };

          # home-assistant.service = {
          #   image = cfg.images.home-assistant;
          #   networks = [ "internal_network" "external_network" ];
          #   restart = "always";
          #   volumes = [
          #     "${cfg.state-directory}/config:config"
          #     "/etc/localtime:/etc/localtime:ro"
          #   ];
          #   ports = [ "${toString cfg.ports.home-assistant}:8123" ];
          #   environment.TZ = config.time.timeZone;
          #   network_mode = "host";
          # };

          node-red.service = {
            image = cfg.images.node-red;
            networks = [ "internal_network" "external_network" ];
            restart = "always";
            volumes = [ "${cfg.state-directory}/node-red:/data" ];
            ports = [ "${toString cfg.ports.node-red}:1880" ];
            environment.TZ = config.time.timeZone;
          };

          open-wake-word.service = {
            image = cfg.images.open-wake-word;
            networks = [ "internal_network" ];
            restart = "always";
            volumes = [ "${cfg.state-directory}/open-wake-word:/data" ];
            environment.TZ = config.time.timeZone;
            command = "--preload-model '${cfg.wake-word}'";
          };

          whisper.service = {
            image = cfg.images.whisper;
            networks = [ "internal_network" ];
            restart = "always";
            volumes = [ "${cfg.state-directory}/whisper:/data" ];
            environment.TZ = config.time.timeZone;
            entrypoint = "python3";
            command = concatStringsSep " " [
              "-m wyoming_faster_whisper"
              "--uri tcp://0.0.0.0:10300"
              "--model tiny-int8"
              "--beam-size 1"
              "--language en"
              "--data-dir /data"
              "--download-dir /data"
            ];
          };

          piper.service = {
            image = cfg.images.piper;
            networks = [ "internal_network" ];
            restart = "always";
            volumes = [ "${cfg.state-directory}/piper:/data" ];
            environment.TZ = config.time.timeZone;
            command = "--voice ${cfg.piper.voice}";
          };
        };
      };
    in { imports = [ image ]; };
  };
}
