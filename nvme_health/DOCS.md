# NVMe Health

Reads the SMART/health log of the NVMe SSD that Home Assistant OS runs on
(`smartctl -x --json /dev/nvme0`) and publishes every value to Home Assistant
via MQTT discovery. All entities appear under one device, **NVMe SSD**.

## Requirements

- The **Mosquitto broker** add-on is installed and running.
- The **MQTT** integration is set up (Home Assistant offers it automatically
  once the broker runs).
- The drive is `/dev/nvme0` (true for a single NVMe SSD, such as a Raspberry Pi 5
  with an NVMe HAT).

## Options

| Option | Default | Meaning |
|---|---|---|
| `interval` | `300` | Seconds between two SMART reads (30 - 86400). |
| `warn_percentage_used` | `80` | Wear level (%) at which **Problem** turns on. |
| `discovery_prefix` | `homeassistant` | MQTT discovery prefix of the MQTT integration. |

## Entities

Entity IDs are fixed (`sensor.nvme_<key>` / `binary_sensor.nvme_<key>`) so
dashboards and automations can be copied as they are.

### Health alarms (binary sensors, device class "problem", ON = problem)

| Entity | Turns ON when |
|---|---|
| `binary_sensor.nvme_problem` | Any alarm below, SMART failed, wear at/above `warn_percentage_used`, media errors > 0, or the newest self-test failed |
| `binary_sensor.nvme_media_read_only` | The drive has put its media into read-only mode (NVMe critical warning bit 3) |
| `binary_sensor.nvme_block_device_read_only` | The Linux kernel marks the disk or one of its partitions read-only (`/sys/block/nvme0n1/.../ro`) |
| `binary_sensor.nvme_data_partition_read_only` | The data partition (seen by the add-on as `/data`) is mounted read-only |
| `binary_sensor.nvme_smart_failed` | SMART overall-health self-assessment is FAILED |
| `binary_sensor.nvme_spare_below_threshold` | Available spare fell below the drive's threshold (bit 0) |
| `binary_sensor.nvme_temperature_warning` | Temperature is above or below a threshold (bit 1) |
| `binary_sensor.nvme_reliability_degraded` | NVM subsystem reliability is degraded (bit 2) |
| `binary_sensor.nvme_volatile_memory_backup_failed` | Volatile memory backup device failed (bit 4) |
| `binary_sensor.nvme_pmr_unreliable` | Persistent memory region is read-only or unreliable (bit 5) |

The two read-only checks show *unknown* if the add-on cannot see the
corresponding sysfs file or mount.

### Sensors

| Entity | Unit | Meaning |
|---|---|---|
| `sensor.nvme_percentage_used` | % | Wear: 0 = new, 100 = rated endurance used up (can exceed 100) |
| `sensor.nvme_available_spare` | % | Remaining spare blocks |
| `sensor.nvme_available_spare_threshold` | % | Spare level below which the drive raises a critical warning |
| `sensor.nvme_data_written_tb` | TB | Total data written (compare with the drive's TBW rating) |
| `sensor.nvme_data_read_tb` | TB | Total data read |
| `sensor.nvme_temperature` | °C | Composite temperature |
| `sensor.nvme_temperature_sensor_N` | °C | Additional temperature sensors reported by the drive |
| `sensor.nvme_warning_temp_time` | min | Time spent above the warning temperature |
| `sensor.nvme_critical_comp_time` | min | Time spent above the critical temperature |
| `sensor.nvme_power_on_hours` | h | Power-on hours |
| `sensor.nvme_power_cycles` | | Power cycles |
| `sensor.nvme_unsafe_shutdowns` | | Power losses without a clean shutdown |
| `sensor.nvme_media_errors` | | Unrecovered data integrity errors |
| `sensor.nvme_num_err_log_entries` | | Error information log entries over the drive's life |
| `sensor.nvme_self_test_status` | | Self-test currently running, if any |
| `sensor.nvme_last_self_test_result` | | Result of the newest self-test in the drive's log |
| `sensor.nvme_host_reads` / `_host_writes` | | Read/write commands (diagnostic) |
| `sensor.nvme_controller_busy_time` | min | Controller busy time (diagnostic) |
| `sensor.nvme_critical_warning` | | Raw critical warning byte (diagnostic) |
| `sensor.nvme_capacity_tb` | TB | Capacity (diagnostic) |
| `sensor.nvme_smartctl_exit_status` | | smartctl exit status bitmask (diagnostic) |

Model, serial number and firmware are shown on the device page.

## Availability

All entities become *unavailable* when the add-on stops, and also when no
update arrived for three poll intervals (for example after a crash), so stale
"healthy" values are never shown.

## Permissions

The add-on maps `/dev/nvme0` and requests the `SYS_ADMIN` capability: Linux
allows reading the NVMe SMART/health log (an admin passthrough command) only
with `CAP_SYS_ADMIN`. smartctl is only used to read; the add-on never writes
to the drive. This lowers the add-on's security rating in the UI.
