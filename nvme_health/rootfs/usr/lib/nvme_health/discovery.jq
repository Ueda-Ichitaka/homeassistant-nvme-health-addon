# Builds the Home Assistant MQTT device discovery payload for one NVMe drive:
# one device with one component (sensor or binary_sensor) per key of the state
# object produced by state.jq. Input is `smartctl -x --json` output.
#
# Arguments:
#   $state               state object from state.jq (decides which components exist)
#   $version             add-on version, reported as origin sw_version
#   $state_topic         MQTT topic the state object is published on
#   $availability_topic  MQTT topic carrying "online"/"offline"
#   $expire_after        seconds without update after which entities go unavailable

# Component metadata per state key. `binary: true` marks problem binary sensors.
def meta: {
    percentage_used: {name: "Wear", icon: "mdi:gauge", unit_of_measurement: "%", state_class: "measurement"},
    available_spare: {name: "Available spare", icon: "mdi:database-check", unit_of_measurement: "%", state_class: "measurement"},
    available_spare_threshold: {name: "Available spare threshold", icon: "mdi:database-alert", unit_of_measurement: "%", entity_category: "diagnostic"},
    temperature: {name: "Temperature", device_class: "temperature", unit_of_measurement: "°C", state_class: "measurement"},
    data_written_tb: {name: "Data written", icon: "mdi:harddisk-plus", device_class: "data_size", unit_of_measurement: "TB", state_class: "total_increasing", suggested_display_precision: 2},
    data_read_tb: {name: "Data read", icon: "mdi:harddisk", device_class: "data_size", unit_of_measurement: "TB", state_class: "total_increasing", suggested_display_precision: 2},
    host_reads: {name: "Host read commands", icon: "mdi:counter", state_class: "total_increasing", entity_category: "diagnostic"},
    host_writes: {name: "Host write commands", icon: "mdi:counter", state_class: "total_increasing", entity_category: "diagnostic"},
    controller_busy_time: {name: "Controller busy time", device_class: "duration", unit_of_measurement: "min", state_class: "total_increasing", entity_category: "diagnostic"},
    power_cycles: {name: "Power cycles", icon: "mdi:power-cycle", state_class: "total_increasing"},
    power_on_hours: {name: "Power-on hours", device_class: "duration", unit_of_measurement: "h", state_class: "total_increasing"},
    unsafe_shutdowns: {name: "Unsafe shutdowns", icon: "mdi:power-plug-off", state_class: "total_increasing"},
    media_errors: {name: "Media errors", icon: "mdi:alert-circle", state_class: "total_increasing"},
    num_err_log_entries: {name: "Error log entries", icon: "mdi:text-box-remove", state_class: "total_increasing"},
    warning_temp_time: {name: "Time above warning temperature", device_class: "duration", unit_of_measurement: "min", state_class: "total_increasing"},
    critical_comp_time: {name: "Time above critical temperature", device_class: "duration", unit_of_measurement: "min", state_class: "total_increasing"},
    critical_warning: {name: "Critical warning", icon: "mdi:alert-octagon", entity_category: "diagnostic"},
    spare_below_threshold: {name: "Spare below threshold", binary: true},
    temperature_warning: {name: "Temperature warning", binary: true},
    reliability_degraded: {name: "Reliability degraded", binary: true},
    media_read_only: {name: "Media read-only", binary: true},
    volatile_memory_backup_failed: {name: "Volatile memory backup failed", binary: true},
    pmr_unreliable: {name: "Persistent memory region unreliable", binary: true},
    smart_failed: {name: "SMART health", binary: true},
    block_device_read_only: {name: "Block device read-only", binary: true},
    data_partition_read_only: {name: "Data partition read-only", binary: true},
    problem: {name: "Problem", binary: true},
    self_test_status: {name: "Self-test status", icon: "mdi:clipboard-pulse"},
    last_self_test_result: {name: "Last self-test result", icon: "mdi:clipboard-check"},
    capacity_tb: {name: "Capacity", icon: "mdi:harddisk", device_class: "data_size", unit_of_measurement: "TB", suggested_display_precision: 2, entity_category: "diagnostic"},
    smartctl_exit_status: {name: "smartctl exit status", icon: "mdi:console", entity_category: "diagnostic"}
};

# Metadata for keys not in the table: numbered temperature sensors.
def meta_for($key):
    meta[$key] // (
        if ($key | startswith("temperature_sensor_")) then
            {name: "Temperature sensor \($key | ltrimstr("temperature_sensor_"))",
             device_class: "temperature", unit_of_measurement: "°C", state_class: "measurement"}
        else {name: $key} end);

.serial_number as $serial
| {
    device: {
        identifiers: ["nvme_health_\($serial)"],
        name: "NVMe SSD",
        model: .model_name,
        serial_number: $serial,
        sw_version: .firmware_version
    },
    origin: {
        name: "NVMe Health",
        sw_version: $version
    },
    state_topic: $state_topic,
    availability_topic: $availability_topic,
    components: ($state | keys | map(
        . as $key
        | meta_for($key) as $m
        | (if $m.binary then "binary_sensor" else "sensor" end) as $platform
        | {key: $key, value: (
            ($m | del(.binary))
            + {
                platform: $platform,
                unique_id: "\($serial)_\($key)",
                default_entity_id: "\($platform).nvme_\($key)",
                value_template: "{{ value_json.\($key) }}",
                expire_after: $expire_after
              }
            + (if $m.binary then {device_class: "problem"} else {} end))}
    ) | from_entries)
}
