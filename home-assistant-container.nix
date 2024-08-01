{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.homeAssistantContainer;

  hostname = config.instance.hostname;

  timezone = config.time.timeZone;

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

  config = mkIf cfg.enable {
    systemd.tmpfiles.settings = {
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

    virtualisation.arion.projects.home-assistant.settings = let
      image = { config, ... }: {
        project.name = "home-assistant";
        docker-compose.volumes = { node-red-data = { }; };
        services = {
          home-assistant = {
            service = {
              restart = "always";
              volumes =
                [ "${cfg.state-directory}/config:/var/lib/home-assistant" ];
              ports = [ "${toString cfg.ports.home-assistant}:8123" ];
              depends_on = [ "node-red" "open-wake-word" "whisper" "piper" ];
              network_mode = "host";
            };
            nixos = {
              useSystemd = true;
              configuration = {
                boot.tmp.useTmpfs = true;
                system.nssModules = mkForce [ ];
                services.home-assistant = {
                  enable = true;
                  package = pkgs.pkgsUnstable.home-assistant;
                  configDir = "/var/lib/home-assistant";
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
                  extraPackages = pyPkgs: with pyPkgs; [ gtts ];
                  customLovelaceModules =
                    with pkgs.home-assistant-custom-lovelace-modules; [
                      android-tv-card
                      button-card
                      mini-graph-card
                      mini-media-player
                      multiple-entity-row
                      mushroom
                    ];
                  customComponents =
                    with pkgs.home-assistant-custom-components; [
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
                    mobile_app = { };
                    http = {
                      server_host = [ "0.0.0.0" ];
                      server_port = 8123;
                      use_x_forwarded_for = true;
                      trusted_proxies = [ "127.0.0.0/16" "10.0.0.0/8" "::1" ];
                    };
                    homeassistant = {
                      name = "Seattle";
                      temperature_unit = "C";
                      time_zone = timezone;
                      unit_system = "metric";
                    } // (optionalAttrs (!isNull cfg.position) {
                      latitude = cfg.position.latitude;
                      longitude = cfg.position.longitude;
                    });
                    nest = mkIf (!isNull cfg.nest) {
                      client_id = cfg.nest.client-id;
                      client_secret = cfg.nest.client-secret;
                      project_id = cfg.nest.project-id;
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
          #   environment.TZ = timezone;
          #   network_mode = "host";
          # };

          node-red.service = {
            image = cfg.images.node-red;
            restart = "always";
            volumes = [ "node-red-data:/data" ];
            ports = [ "${toString cfg.ports.node-red}:1880" ];
            environment.TZ = timezone;
          };

          open-wake-word.service = {
            image = cfg.images.open-wake-word;
            restart = "always";
            volumes = [ "${cfg.state-directory}/open-wake-word:/data" ];
            environment.TZ = timezone;
            command = "--preload-model '${cfg.wake-word}'";
          };

          whisper.service = {
            image = cfg.images.whisper;
            restart = "always";
            volumes = [ "${cfg.state-directory}/whisper:/data" ];
            environment.TZ = timezone;
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
            restart = "always";
            volumes = [ "${cfg.state-directory}/piper:/data" ];
            environment.TZ = timezone;
            command = "--voice ${cfg.piper.voice}";
          };
        };
      };
    in { imports = [ image ]; };
  };
}
