# Home Assistant Container (Nix Flake)

A declarative, reproducible NixOS module for running Home Assistant in containers with integrated voice assistant capabilities.

## Overview

This Nix flake provides a complete Home Assistant setup with:

- **Home Assistant Core** - Full smart home automation platform
- **Voice Integration** - Local wake word detection; STT/TTS served by the k8s
  `wyoming` namespace rather than by this module (see below)
- **Visual Automation** - Node-Red for creating automation flows
- **Extensive Integrations** - 50 built-in components for smart home devices
- **Custom Components** - Frigate, ntfy, Prometheus sensor, Node-Red and
  NoLongerEvil (for Nest thermostats too old for Google's SDM API)
- **Declarative Configuration** - Everything configured as code for reproducibility

All services run in Docker containers managed through [Arion](https://docs.hercules-ci.com/arion/) (Nix's declarative Docker Compose wrapper).

## Architecture

The flake deploys 3 containerized services:

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
           └──► Open-Wake-Word (Port 10400)
                Wake word detection (e.g., "hey jarvis")

     STT and TTS are NOT containers here. They are served by the
     k8s `wyoming` namespace over Tailscale -- see "Voice Assistant
     Setup" below. Local whisper and piper were removed 2026-07-10.
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
- **nixpkgs** matching this flake's release (`nixos-26.05`); point the flake's `nixpkgs` input at yours with `inputs.nixpkgs.follows = "nixpkgs"`
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

### 3. Share your nixpkgs (Recommended)

Nothing extra to add: the module takes every Home Assistant package from your
own `pkgs`, and its `nixosModules.default` already appends the overlay it needs
(`home-assistant-local-components`, plus an aiounittest fix for the Python 3.14
interpreter set home-assistant builds from).

Do make this flake follow your nixpkgs, so there is one instance rather than two:

```nix
inputs.home-assistant-container = {
  url = "github:fudoniten/home-assistant-container";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Earlier versions asked you to add a `pkgsUnstable` overlay and instantiated a
second nixpkgs internally, with `python3` pinned to 3.13. That put everything
downstream of `python3` -- `meson`, and therefore most of the tree -- outside
cache.nixos.org, so the host rebuilt it from source. Neither is needed now; if
you still carry that overlay for this module, drop it.

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

### Built-in Home Assistant Components (50)

- **Smart Home**: ESPHome, MQTT, HomeKit Controller, Chromecast, Android TV
- **Weather**: Met.no, AccuWeather
- **Voice**: OpenAI Conversation, OpenRouter, Ollama, MaryTTS, Wyoming
- **Media**: Spotify, Pocketcasts, Radio Browser, MPD, Music Assistant
- **Network**: Nmap Tracker, UPnP, AdGuard Home
- **Security**: August Locks
- **Monitoring**: Prometheus metrics, Energy tracking
- **Printers**: Brother, IPP
- **Other**: Synology DSM, Tile tracker, Coinbase, Kraken, Minecraft

### Custom Components

- **Node-Red** - Visual automation flow editor (built by this flake)
- **NoLongerEvil** - Nest thermostats running No Longer Evil firmware, for
  hardware too old for Google's SDM API (built by this flake)
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

1. Check the wake word service is running:
   ```bash
   docker ps | grep wake-word
   ```

2. Test the local Wyoming endpoint:
   ```bash
   curl http://localhost:10400  # open-wake-word
   ```

3. STT and TTS are not local. Check the cluster endpoints instead:
   ```bash
   curl https://stt.kube.sea.fudo.link/v1/models
   curl https://tts.kube.sea.fudo.link/v1/models
   ```

4. Check Home Assistant Wyoming integration configuration

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
mqtt_password: "your-secret"
```

Reference in configuration:
```nix
{
  services.homeAssistantContainer.extraConfig = ''
    mqtt:
      password: !secret mqtt_password
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
- [openWakeWord](https://github.com/dscripka/openWakeWord) - Wake word detection
- [Node-Red](https://nodered.org/) - Visual flow-based programming

## Acknowledgments

- Custom components by: zachowj (Node-Red), patricktr (NoLongerEvil)
- Wake word detection from the Rhasspy/Wyoming ecosystem
