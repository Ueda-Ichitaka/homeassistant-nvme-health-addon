#!/usr/bin/env bats
# Tests for state.jq: turns `smartctl -x --json` output of an NVMe drive into
# the flat state object that is published to MQTT for the Home Assistant sensors.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../nvme_health/rootfs/usr/lib/nvme_health"
    FIX="${BATS_TEST_DIRNAME}/fixtures"
    BLOCK_RO=OFF
    DATA_RO=OFF
    WARN_USED=80
}

# Prints the state for fixture $1, after applying the optional jq filter $2
# to the fixture (used to simulate failing drives).
state_for() {
    jq "${2:-.}" "${FIX}/$1" \
        | jq -c --arg block_ro "${BLOCK_RO}" --arg data_ro "${DATA_RO}" \
            --argjson warn_percentage_used "${WARN_USED}" \
            -f "${LIB}/state.jq"
}

# Prints key $2 of the state for fixture $1 (optional fixture filter $3).
state_of() {
    state_for "$1" "${3:-.}" | jq -r ".$2"
}

# Fixture filter: sets the NVMe critical warning byte to $1.
critical_warning() {
    echo ".nvme_smart_health_information_log.critical_warning = $1"
}

@test "copies the NVMe health log counters" {
    [ "$(state_of smartctl_nvme0.json percentage_used)" = "1" ]
    [ "$(state_of smartctl_nvme0.json available_spare)" = "100" ]
    [ "$(state_of smartctl_nvme0.json available_spare_threshold)" = "10" ]
    [ "$(state_of smartctl_nvme0.json temperature)" = "33" ]
    [ "$(state_of smartctl_nvme0.json power_on_hours)" = "2368" ]
    [ "$(state_of smartctl_nvme0.json power_cycles)" = "246" ]
    [ "$(state_of smartctl_nvme0.json unsafe_shutdowns)" = "49" ]
    [ "$(state_of smartctl_nvme0.json media_errors)" = "0" ]
    [ "$(state_of smartctl_nvme1.json num_err_log_entries)" = "1" ]
    [ "$(state_of smartctl_nvme0.json host_reads)" = "317987839" ]
    [ "$(state_of smartctl_nvme0.json host_writes)" = "341724947" ]
    [ "$(state_of smartctl_nvme0.json controller_busy_time)" = "55" ]
    [ "$(state_of smartctl_nvme0.json warning_temp_time)" = "0" ]
    [ "$(state_of smartctl_nvme0.json critical_comp_time)" = "0" ]
}

@test "converts data units (512000 bytes each) to terabytes" {
    # 17373726 units * 512000 B = 8.895347712 TB
    [ "$(state_of smartctl_nvme0.json data_written_tb)" = "8.895347712" ]
    # 31035853 units * 512000 B = 15.890356736 TB
    [ "$(state_of smartctl_nvme0.json data_read_tb)" = "15.890356736" ]
}

@test "reports capacity in terabytes and the smartctl exit status" {
    [ "$(state_of smartctl_nvme0.json capacity_tb)" = "2.000398934016" ]
    [ "$(state_of smartctl_nvme0.json smartctl_exit_status)" = "0" ]
}

@test "exposes every extra temperature sensor as its own key" {
    [ "$(state_of smartctl_nvme0.json temperature_sensor_1)" = "33" ]
    [ "$(state_of smartctl_nvme0.json temperature_sensor_2)" = "42" ]
    [ "$(state_of smartctl_nvme0.json temperature_sensor_3)" = "null" ]
}

@test "healthy drive has all warning flags OFF" {
    for key in spare_below_threshold temperature_warning reliability_degraded \
               media_read_only volatile_memory_backup_failed pmr_unreliable \
               smart_failed block_device_read_only data_partition_read_only problem; do
        [ "$(state_of smartctl_nvme0.json "${key}")" = "OFF" ] || { echo "${key} not OFF"; false; }
    done
    [ "$(state_of smartctl_nvme0.json critical_warning)" = "0" ]
}

@test "critical warning bit 3 turns media_read_only and problem ON" {
    filter="$(critical_warning 8)"
    [ "$(state_of smartctl_nvme0.json media_read_only "${filter}")" = "ON" ]
    [ "$(state_of smartctl_nvme0.json problem "${filter}")" = "ON" ]
    [ "$(state_of smartctl_nvme0.json reliability_degraded "${filter}")" = "OFF" ]
    [ "$(state_of smartctl_nvme0.json critical_warning "${filter}")" = "8" ]
}

@test "each critical warning bit maps to its own flag" {
    [ "$(state_of smartctl_nvme0.json spare_below_threshold "$(critical_warning 1)")" = "ON" ]
    [ "$(state_of smartctl_nvme0.json temperature_warning "$(critical_warning 2)")" = "ON" ]
    [ "$(state_of smartctl_nvme0.json reliability_degraded "$(critical_warning 4)")" = "ON" ]
    [ "$(state_of smartctl_nvme0.json volatile_memory_backup_failed "$(critical_warning 16)")" = "ON" ]
    [ "$(state_of smartctl_nvme0.json pmr_unreliable "$(critical_warning 32)")" = "ON" ]
    [ "$(state_of smartctl_nvme0.json media_read_only "$(critical_warning 32)")" = "OFF" ]
}

@test "failed SMART overall assessment turns smart_failed and problem ON" {
    filter='.smart_status.passed = false'
    [ "$(state_of smartctl_nvme0.json smart_failed "${filter}")" = "ON" ]
    [ "$(state_of smartctl_nvme0.json problem "${filter}")" = "ON" ]
}

@test "wear at or above the configured limit turns problem ON" {
    WARN_USED=1
    [ "$(state_of smartctl_nvme0.json problem)" = "ON" ]
    WARN_USED=2
    [ "$(state_of smartctl_nvme0.json problem)" = "OFF" ]
}

@test "media errors turn problem ON" {
    [ "$(state_of smartctl_nvme0.json problem '.nvme_smart_health_information_log.media_errors = 3')" = "ON" ]
}

@test "kernel read-only flag of the block device is reported and turns problem ON" {
    BLOCK_RO=ON
    [ "$(state_of smartctl_nvme0.json block_device_read_only)" = "ON" ]
    [ "$(state_of smartctl_nvme0.json problem)" = "ON" ]
}

@test "read-only /data mount is reported and turns problem ON" {
    DATA_RO=ON
    [ "$(state_of smartctl_nvme0.json data_partition_read_only)" = "ON" ]
    [ "$(state_of smartctl_nvme0.json problem)" = "ON" ]
}

@test "unknown read-only checks are null and do not raise problem" {
    BLOCK_RO=unknown
    DATA_RO=unknown
    [ "$(state_of smartctl_nvme0.json block_device_read_only)" = "null" ]
    [ "$(state_of smartctl_nvme0.json data_partition_read_only)" = "null" ]
    [ "$(state_of smartctl_nvme0.json problem)" = "OFF" ]
}

@test "reports the current self-test operation" {
    [ "$(state_of smartctl_nvme0.json self_test_status)" = "No self-test in progress" ]
}

@test "reports the newest self-test result, or none" {
    [ "$(state_of smartctl_nvme0.json last_self_test_result)" = "No self-test logged" ]
    filter='.nvme_self_test_log.table = [
        {"self_test_code": {"value": 1, "string": "Short"},
         "self_test_result": {"value": 7, "string": "Completed: failed segments"},
         "power_on_hours": 2300},
        {"self_test_code": {"value": 1, "string": "Short"},
         "self_test_result": {"value": 0, "string": "Completed without error"},
         "power_on_hours": 2200}]'
    [ "$(state_of smartctl_nvme0.json last_self_test_result "${filter}")" = "Completed: failed segments" ]
}

@test "a failed newest self-test turns problem ON" {
    filter='.nvme_self_test_log.table = [
        {"self_test_code": {"value": 1, "string": "Short"},
         "self_test_result": {"value": 7, "string": "Completed: failed segments"},
         "power_on_hours": 2300}]'
    [ "$(state_of smartctl_nvme0.json problem "${filter}")" = "ON" ]
}

@test "an aborted newest self-test does not raise problem" {
    filter='.nvme_self_test_log.table = [
        {"self_test_code": {"value": 1, "string": "Short"},
         "self_test_result": {"value": 2, "string": "Aborted: Controller Reset"},
         "power_on_hours": 2300}]'
    [ "$(state_of smartctl_nvme0.json problem "${filter}")" = "OFF" ]
}
