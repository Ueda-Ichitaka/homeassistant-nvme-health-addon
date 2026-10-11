# NVMe Health - Home Assistant add-on

Monitors the NVMe SSD that Home Assistant OS runs on (for example a Raspberry
Pi 5 with an NVMe HAT). It reads the full NVMe SMART/health log with
`smartctl` and publishes it to Home Assistant via MQTT discovery. That includes:

- wear, available spare, terabytes written and read
- temperatures, power-on hours, unsafe shutdowns, media errors
- every NVMe critical warning bit as its own alarm, including
  **media read-only mode**
- the kernel's read-only flag of the disk and its partitions, and whether the
  data partition is mounted read-only

See [nvme_health/DOCS.md](nvme_health/DOCS.md) for the full list of entities
and [examples/dashboard.yaml](examples/dashboard.yaml) for a ready-made dashboard.

## Installation

1. Install and start the **Mosquitto broker** add-on, then set up the **MQTT**
   integration that Home Assistant offers.
2. Add this repository: Settings > Add-ons > Add-on store > three dots >
   Repositories, paste the repository URL.
   For a local install instead, copy the `nvme_health` folder into the `/addons`
   share of Home Assistant (Samba or SSH add-on) and reload the add-on store.
3. Install **NVMe Health**, start it, and open Settings > Devices > MQTT >
   **NVMe SSD**.

## Layout

```
nvme_health/            the add-on (built on the Home Assistant host)
  config.yaml           manifest: options, device mapping, SYS_ADMIN capability
  Dockerfile            HA Alpine base + smartmontools + mosquitto-clients
  rootfs/usr/lib/nvme_health/
    state.jq            smartctl JSON -> flat state object
    discovery.jq        smartctl JSON + state -> MQTT device discovery payload
    functions.sh        host checks, poll cycle, MQTT publishing
  rootfs/usr/bin/nvme_health   main loop (bashio glue)
tests/                  bats test suite with real smartctl fixtures
examples/               dashboard example
```

## Development

Tests run in Docker, so only Docker is needed:

```sh
./run-tests.sh                      # whole suite
./run-tests.sh tests/state.bats     # one file
```
