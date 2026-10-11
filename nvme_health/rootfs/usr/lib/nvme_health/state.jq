# Turns `smartctl -x --json` output of an NVMe drive into the flat state object
# published on the MQTT state topic; every Home Assistant sensor reads one key.
#
# Arguments:
#   $block_ro              "ON"/"OFF"/"unknown": kernel read-only flag of the block device
#   $data_ro               "ON"/"OFF"/"unknown": /data of this add-on is mounted read-only
#   $warn_percentage_used  wear level (percent) from which `problem` turns ON

def onoff: if . then "ON" else "OFF" end;

# True when bit `$b` (0-7) of the integer input is set (jq has no bitwise operators).
def bit($b): (. / pow(2; $b) | floor) % 2 == 1;

# NVMe data units are 1000 * 512 bytes.
def units_to_tb: . * 512000 / 1e12;

# "ON"/"OFF" pass through, anything else (e.g. "unknown") becomes null.
def known_onoff: if . == "ON" or . == "OFF" then . else null end;

# NVMe self-test result codes that mean the drive failed the test
# (0x5 fatal error, 0x6 unknown failed segment, 0x7 failed segments).
def self_test_failed: . == 5 or . == 6 or . == 7;

.nvme_smart_health_information_log as $log
| ($log.critical_warning // 0) as $cw
| ((.nvme_self_test_log.table // [])[0]) as $last_test
| {
    percentage_used: $log.percentage_used,
    available_spare: $log.available_spare,
    available_spare_threshold: $log.available_spare_threshold,
    temperature: $log.temperature,
    data_written_tb: ($log.data_units_written | units_to_tb),
    data_read_tb: ($log.data_units_read | units_to_tb),
    host_reads: $log.host_reads,
    host_writes: $log.host_writes,
    controller_busy_time: $log.controller_busy_time,
    power_cycles: $log.power_cycles,
    power_on_hours: $log.power_on_hours,
    unsafe_shutdowns: $log.unsafe_shutdowns,
    media_errors: $log.media_errors,
    num_err_log_entries: $log.num_err_log_entries,
    warning_temp_time: $log.warning_temp_time,
    critical_comp_time: $log.critical_comp_time,
    critical_warning: $cw,
    spare_below_threshold: ($cw | bit(0) | onoff),
    temperature_warning: ($cw | bit(1) | onoff),
    reliability_degraded: ($cw | bit(2) | onoff),
    media_read_only: ($cw | bit(3) | onoff),
    volatile_memory_backup_failed: ($cw | bit(4) | onoff),
    pmr_unreliable: ($cw | bit(5) | onoff),
    smart_failed: (.smart_status.passed == false | onoff),
    block_device_read_only: ($block_ro | known_onoff),
    data_partition_read_only: ($data_ro | known_onoff),
    self_test_status: .nvme_self_test_log.current_self_test_operation.string,
    last_self_test_result: ($last_test.self_test_result.string // "No self-test logged"),
    capacity_tb: (.user_capacity.bytes / 1e12),
    smartctl_exit_status: .smartctl.exit_status
  }
+ ([$log.temperature_sensors // [] | to_entries[]
    | {key: "temperature_sensor_\(.key + 1)", value: .value}] | from_entries)
| .problem = (
    [.critical_warning != 0, .smart_failed == "ON",
     .percentage_used >= $warn_percentage_used,
     .media_errors > 0,
     .block_device_read_only == "ON", .data_partition_read_only == "ON",
     ($last_test.self_test_result.value // 0 | self_test_failed)]
    | any | onoff)
