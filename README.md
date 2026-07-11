# Home Assistant Container (Nix Flake)

A declarative, reproducible NixOS module for running Home Assistant in containers with integrated voice assistant capabilities.

## Overview

This Nix flake provides a complete Home Assistant setup with:

- **Home Assistant Core** - Full smart home automation platform
- **Voice Integration** - Wake word detection, speech-to-text, and text-to-speech
- **Visual Automation** - Node-Red for creating automation flows
- **Extensive Integrations** - 30+ built-in components for smart home devices
- **Custom Components** - Extended OpenAI Conversation, OpenAI TTS, and Node-Red integration
- **Declarative Configuration** - Everything configured as code for reproducibility

All services run in Docker containers managed through [Arion](https://docs.hercules-ci.com/arion/) (Nix's declarative Docker Compose wrapper).

## Architecture

The flake deploys 5 containerized services:

```
┌─────────────────────────────────────────────┐
│  Home Assistant (Main Hub)                  │
│  Port: 8123                                 │
│  Network: Host mode (for device discovery) │
└─────────────────────────────────────────────┘
           │
           ├──► Node-Red (Port 1880)
           │    Visual automation flows
           │
           ├──► Open-Wake-Word (Port 10400)
           │    Wake word detection (e.g., "hey jarvis")
           │
           ├──► Whisper (Port 10300)
           │    Speech-to-text using OpenAI Whisper
           │
           └──► Piper (Port 10200)
                Text-to-speech voice synthesis
```

### Why Host Network Mode?

Home Assistant runs with `network_mode = "host"` to enable:
- **mDNS/Zeroconf device discovery** - Automatically find devices on your network
- **UPnP/DLNA support** - Detect media players and smart TVs
- **Local API access** - Services like ESPHome need direct network access
- **Multicast protocols** - Required for many IoT device protocols

**Security Note**: Host mode removes container network isolation. Ensure your NixOS firewall is properly configured to limit access to Home Assistant's port 8123.

## Prerequisites

- **NixOS** with flakes enabled
- **nixpkgs unstable overlay** for Home Assistant packages (see Configuration section)
- **Docker/Podman** support (automatically configured through Arion)
- **Sufficient disk space** for container images and Home Assistant state

## Installation

### 1. Add to your flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-assistant-container.url = "github:fudoniten/home-assistant-container";
  };
}
```

### 2. Import the NixOS module

```nix
{
  outputs = { self, nixpkgs, home-assistant-container, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-assistant-container.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### 3. Add nixpkgs-unstable overlay (Required)

Home Assistant requires packages from nixpkgs-unstable. Add this to your configuration:

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      pkgsUnstable = import inputs.nixpkgs-unstable {
        system = prev.system;
        config.allowUnfree = true;
      };
    })
  ];
}
```

## Configuration

### Minimal Configuration

```nix
{
  services.homeAssistantContainer = {
    enable = true;

    # Required: Where to store Home Assistant data
    state-directory = "/var/lib/home-assistant";

    # Required: Your location for weather, sunrise/sunset, etc.
    position = {
      latitude = 47.6062;   # Seattle, WA
      longitude = -122.3321;
    };
  };
}
```

### Full Configuration Example

```nix
{
  services.homeAssistantContainer = {
    enable = true;
    state-directory = "/var/lib/home-assistant";

    # Display name
    name = "My Smart Home";

    # Location configuration
    position = {
      latitude = 47.6062;
      longitude = -122.3321;
    };

    # Network configuration
    trusted-proxies = [ "127.0.0.0/16" "10.0.0.0/16" "::1" ];

    # Prometheus metrics (set to null to disable)
    prometheus = {
      requires-auth = false;  # Set to true for authentication
    };

    # Port mappings (defaults shown)
    ports = {
      home-assistant = 8123;
      node-red = 1880;
    };

    # Voice assistant configuration
    # Wake word: local openwakeword container (this module)
    wake-word = "hey_jarvis";  # Wake word model name
    # STT/TTS: k8s wyoming namespace — see "Voice Assistant Setup" below.

    # Nest thermostat credentials (optional)
    nest = {
      project-id = "your-project-id";
      client-id = "your-client-id";
      client-secret = "your-client-secret";
    };

    # Additional YAML configuration merged into configuration.yaml
    extraConfig = ''
      # Add any additional Home Assistant configuration here
      automation: !include automations.yaml

      notify:
        - platform: ntfy
          url: https://ntfy.sh
          topic: your-topic
    '';

    # Import additional configuration files
    extraImports = [
      "secrets.yaml"
      "customize.yaml"
    ];

    # Custom voice commands (simple sentences)
    customSimpleSentences = ''
      language: "en"
      intents:
        TurnOnTV:
          data:
            - sentences:
                - "turn on [the] TV"
                - "TV on"
    '';

    # Override container images (optional)
    images = {
      home-assistant = "ghcr.io/home-assistant/home-assistant:stable";
      node-red = "nodered/node-red:latest";
      # ... other services
    };
  };
}
```

### Voice Assistant Setup

The voice integration has three pieces:

1. **Open-Wake-Word** (local container, this module) — Listens for wake word (default: "hey jarvis")
   - Available models: hey_jarvis, ok_nabu, alexa, hey_mycroft, hey_rhasspy
   - Configure with: `services.homeAssistantContainer.wake-word`

2. **Speech-to-Text** (NOT in this module) — Use the k8s `wyoming` namespace
   - Service: `whisper-http.wyoming.svc.cluster.local:10301` (OpenAI-compat)
   - Exposed externally as `stt.kube.sea.fudo.link` (or `stt.fudo.ninja` over Tailscale)
   - Model: `turbo` (preloaded on GPU, 2Ti PVC for model cache)
   - In HA: add the `openai_whisper` integration with `base_url: https://stt.kube.sea.fudo.link/v1`

3. **Text-to-Speech** (NOT in this module) — Use the k8s `wyoming` namespace
   - Service: `kokoro-tts.wyoming.svc.cluster.local:8880` (OpenAI-compat)
   - Exposed externally as `tts.kube.sea.fudo.link` (or `tts.fudo.ninja` over Tailscale)
   - Voices: `af_heart`, `af_bella`, `am_adam`, `bm_george`, and more
   - In HA: add the `openai` TTS integration with `base_url: https://tts.kube.sea.fudo.link/v1`, `voice: af_heart`

> **Why:** local whisper/piper containers were removed (2026-07-10) because they were
> not on wormhole0's audio path — HA was using the k8s stack via Tailscale. The local
> containers consumed resources and generated journal noise without serving requests.
> This module still ships `home-assistant`, `node-red`, and `open-wake-word` locally;
> STT/TTS are now exclusively cluster-side.

## Included Components

### Built-in Home Assistant Components (30+)

- **Smart Home**: ESPHome, MQTT, HomeKit Controller, Chromecast, Android TV
- **Weather**: Met.no, AccuWeather
- **Voice**: OpenAI Conversation, Extended OpenAI Conversation, MaryTTS
- **Media**: Spotify, Pocketcasts, Radio Browser, MPD, Music Assistant
- **Network**: Nmap Tracker, UPnP, AdGuard Home
- **Security**: August Locks, Nest
- **Monitoring**: Prometheus metrics, Energy tracking
- **Printers**: Brother, IPP
- **Other**: Synology DSM, Tile tracker, Coinbase, Kraken, Minecraft

### Custom Components

- **Node-Red** - Visual automation flow editor
- **Extended OpenAI Conversation** - Enhanced AI conversation with function calling
- **OpenAI TTS** - Text-to-speech using OpenAI voices
- **Frigate** - NVR with object detection
- **Ntfy** - Simple notification service
- **Prometheus Sensor** - Custom Prometheus metrics

### Custom Lovelace UI Cards

- Bubble Card, Button Card, Card Mod
- Mini Graph Card, Mini Media Player
- Multiple Entity Row, Mushroom, Weather Card

## File Structure

```
/var/lib/home-assistant/          # State directory (configurable)
├── configuration.yaml             # Auto-generated from Nix config
├── custom_sentences/             # Voice command definitions
│   └── en/
│       ├── sentences.yaml        # Simple sentence patterns
│       ├── custom_sentences.yaml # User-defined sentences
│       └── intents.yaml          # Intent handlers
├── automations.yaml              # Your automations
├── scripts.yaml                  # Your scripts
└── ...                           # Other Home Assistant files
```

## Networking & Firewall

Home Assistant uses host network mode, so configure your firewall:

```nix
{
  networking.firewall = {
    allowedTCPPorts = [
      8123   # Home Assistant web interface
      1880   # Node-Red (optional, for remote access)
    ];
    allowedUDPPorts = [
      5353   # mDNS for device discovery
    ];
  };
}
```

## Updating

Update all dependencies:

```bash
nix flake update
```

Update specific input:

```bash
nix flake lock --update-input home-assistant-container
```

Rebuild your system:

```bash
sudo nixos-rebuild switch --flake .#your-host
```

## Troubleshooting

### Container fails to start

Check logs:
```bash
journalctl -u arion-home-assistant.service -f
```

### Home Assistant can't find devices

- Ensure host network mode is enabled (default)
- Check your firewall allows mDNS (UDP port 5353)
- Verify devices are on the same network segment

### Voice assistant not working

1. Check all voice services are running:
   ```bash
   docker ps | grep -E "whisper|piper|wake-word"
   ```

2. Test Wyoming protocol endpoints:
   ```bash
   curl http://localhost:10300  # Whisper
   curl http://localhost:10200  # Piper
   ```

3. Check Home Assistant Wyoming integration configuration

### Permission errors

Ensure state directory has correct permissions:
```bash
sudo chown -R 568:568 /var/lib/home-assistant  # UID 568 is Home Assistant in container
```

## Advanced Configuration

### Using Secrets

Store sensitive data in `secrets.yaml`:

```yaml
# /var/lib/home-assistant/secrets.yaml
nest_project_id: "your-secret-project-id"
nest_client_secret: "your-secret"
```

Reference in configuration:
```nix
{
  services.homeAssistantContainer.extraConfig = ''
    nest:
      project_id: !secret nest_project_id
      client_secret: !secret nest_client_secret
  '';

  services.homeAssistantContainer.extraImports = [ "secrets.yaml" ];
}
```

### Custom Component Development

Add your own custom component:

```nix
{
  services.homeAssistantContainer.extraConfig = ''
    # Your custom component will be loaded from:
    # /var/lib/home-assistant/custom_components/your_component/
  '';
}
```

Place your component files in:
```
/var/lib/home-assistant/custom_components/your_component/
├── __init__.py
├── manifest.json
└── ...
```

## Contributing

Issues and pull requests welcome at: https://github.com/fudoniten/home-assistant-container

## License

This project follows the license of its components:
- Home Assistant: Apache License 2.0
- This flake configuration: [Your chosen license]

## Related Projects

- [Home Assistant](https://www.home-assistant.io/) - Open source home automation
- [Arion](https://docs.hercules-ci.com/arion/) - Nix-based Docker Compose
- [Whisper](https://github.com/openai/whisper) - OpenAI speech recognition
- [Piper](https://github.com/rhasspy/piper) - Fast text-to-speech
- [Node-Red](https://nodered.org/) - Visual flow-based programming

## Acknowledgments

- Custom components by: jekalmin (Extended OpenAI), sfortis (OpenAI TTS), zachowj (Node-Red)
- Voice services from the Rhasspy/Wyoming ecosystem
