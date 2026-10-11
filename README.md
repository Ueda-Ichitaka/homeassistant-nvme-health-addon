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

## Setup

Home Assistant calls add-ons **apps** in its current UI (Settings > Apps); the
steps below use those menu names.

### Prerequisites

- **Home Assistant OS** (apps need the Supervisor; Home Assistant Container or
  Core installations cannot run them).
- An **NVMe SSD available as `/dev/nvme0`**, normally the drive Home Assistant OS
  boots from, such as on a Raspberry Pi 5 with an NVMe HAT. Architectures:
  `aarch64` and `amd64`.
- An **MQTT broker** and the **MQTT integration**, set up as described next.

### Step 1: Install the Mosquitto broker

Skip this step if Mosquitto is already running and the MQTT integration is set up.

1. Go to **Settings > Apps** and select **Install app**.
2. Find **Mosquitto broker**, open it and select **Install**.
3. On the app's **Info** tab, enable **Start on boot** and **Watchdog**, then
   select **Start**.
4. Open the **Log** tab and wait until the broker reports that it is running
   (this can take a minute or two).

No MQTT user has to be created for NVMe Health: the app requests the broker
from the Supervisor, which hands it its own credentials automatically. A user
under **Settings > People > Users** is only needed for MQTT devices outside
Home Assistant (the names `homeassistant` and `addons` are reserved).

### Step 2: Set up the MQTT integration

1. Go to **Settings > Devices & services**.
2. **MQTT** appears as a discovered integration at the top of the page. Select
   **Add** and confirm with **Submit**.
   If it does not appear, select **Add integration**, search for **MQTT** and
   pick the Mosquitto broker app.
3. Leave MQTT discovery enabled (the default). If you change the discovery
   prefix (MQTT integration > **Configure**, dialog "MQTT options", default
   `homeassistant`), set the same value in the NVMe Health option
   `discovery_prefix`.

### Step 3: Add this repository

1. Go to **Settings > Apps** and select **Install app**.
2. In the top-right corner, open the three-dots menu and select **Repositories**.
3. Paste the HTTPS clone URL of this git repository and select **Add**.
4. Close the dialog and refresh the page. A card for **NVMe Health add-on
   repository** appears in the store.

**Alternative, without publishing the repository (local app):**

1. Install and start the **Samba share** or **Terminal & SSH** app.
2. Copy the `nvme_health` folder into the `local_apps` share (Samba) or the
   `/local_apps` directory (SSH), so that `local_apps/nvme_health/config.yaml`
   exists.
3. Go to **Settings > Apps > Install app**, open the three-dots menu, select
   **Check for updates** and refresh the page. **NVMe Health** appears under
   **Local apps**.
4. If it does not appear, check **Settings > System > Logs**, select
   **Supervisor** and look for a validation error near the end of the log.

### Step 4: Install and configure NVMe Health

1. Open **NVMe Health** in the store and select **Install**. Home Assistant
   builds the image on your device, which takes a few minutes on a Raspberry Pi.
2. Optionally adjust the options on the **Configuration** tab:

   | Option | Default | Meaning |
   |---|---|---|
   | `interval` | `300` | Seconds between two SMART reads (30 - 86400). Entities go unavailable after three missed reads. |
   | `warn_percentage_used` | `80` | Wear level (%) at which the **Problem** alarm turns on. |
   | `discovery_prefix` | `homeassistant` | Must match the MQTT integration's discovery prefix. |

3. On the **Info** tab, enable **Start on boot** and **Watchdog**, then select
   **Start**.
4. Open the **Log** tab. A healthy start looks like:

   ```
   Monitoring /dev/nvme0 every 300s, MQTT broker core-mosquitto:1883
   Published discovery for <your SSD model> (<serial>)
   ```

The app asks for access to `/dev/nvme0` and the `SYS_ADMIN` capability, because
Linux only allows reading the NVMe SMART/health log with that capability. This
lowers the app's security rating shown in the UI. The app only reads from the
drive.

### Step 5: Check the entities and add the dashboard

1. Go to **Settings > Devices & services > MQTT** and open the device
   **NVMe SSD**. It lists all sensors and alarms; entity IDs start with
   `sensor.nvme_` and `binary_sensor.nvme_` (see
   [DOCS.md](nvme_health/DOCS.md) for the full list).
2. For the example dashboard, go to **Settings > Dashboards**, select
   **Add dashboard** > **New dashboard from scratch**, and open it. Select the
   pencil (edit) icon, open the three-dots menu, choose **Raw configuration
   editor**, and add the content of
   [examples/dashboard.yaml](examples/dashboard.yaml) as an entry of `views:`.
3. Recommended: create an automation that notifies you when
   `binary_sensor.nvme_problem` turns on, or when it becomes unavailable
   (the app stopped or cannot reach the broker).

### Troubleshooting

| Symptom in the app log | Cause and fix |
|---|---|
| `No MQTT broker found` | Mosquitto is not installed or not running: repeat steps 1 and 2. |
| `smartctl could not read /dev/nvme0 ... Permission denied` | The drive or the capability is not available to the app. Restart the app; if it persists, reboot the host and open an issue with the log. |
| `smartctl could not read /dev/nvme0 ... No such file or directory` | There is no NVMe drive at `/dev/nvme0` on this host. |
| Entities exist but stay *unavailable* | The app is stopped or cannot publish: check its log and the Mosquitto log. |
| Read-only alarms show *unknown* | The app cannot see the sysfs flag or the `/data` mount on this system; all other entities still work. |

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

## License

[MIT](LICENSE)
