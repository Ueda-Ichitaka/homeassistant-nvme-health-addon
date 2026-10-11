#!/usr/bin/env bats
# Tests for discovery.jq: builds the Home Assistant MQTT device discovery payload
# (one device, one component per state key) from smartctl output and the state.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../nvme_health/rootfs/usr/lib/nvme_health"
    FIX="${BATS_TEST_DIRNAME}/fixtures"
    STATE="$(jq -c --arg block_ro OFF --arg data_ro unknown --argjson warn_percentage_used 80 \
        -f "${LIB}/state.jq" "${FIX}/smartctl_nvme0.json")"
    DISCOVERY="$(jq -c --argjson state "${STATE}" --arg version 1.2.3 \
        --arg state_topic nvme_health/TESTSERIAL0000/state \
        --arg availability_topic nvme_health/TESTSERIAL0000/availability \
        --argjson expire_after 960 \
        -f "${LIB}/discovery.jq" "${FIX}/smartctl_nvme0.json")"
}

# Prints the result of jq filter $1 applied to the discovery payload.
d() {
    echo "${DISCOVERY}" | jq -r "$1"
}

@test "describes the drive as one device" {
    [ "$(d '.device.identifiers[0]')" = "nvme_health_TESTSERIAL0000" ]
    [ "$(d '.device.name')" = "NVMe SSD" ]
    [ "$(d '.device.model')" = "Lexar SSD NQ790 2TB" ]
    [ "$(d '.device.serial_number')" = "TESTSERIAL0000" ]
    [ "$(d '.device.sw_version')" = "1.7.O.4F" ]
}

@test "names the add-on as origin" {
    [ "$(d '.origin.name')" = "NVMe Health" ]
    [ "$(d '.origin.sw_version')" = "1.2.3" ]
}

@test "shares state and availability topics across components" {
    [ "$(d '.state_topic')" = "nvme_health/TESTSERIAL0000/state" ]
    [ "$(d '.availability_topic')" = "nvme_health/TESTSERIAL0000/availability" ]
}

@test "has exactly one component per state key" {
    [ "$(d '.components | keys | join(",")')" = "$(echo "${STATE}" | jq -r 'keys | join(",")')" ]
}

@test "every component reads its own key, has a unique id and expires" {
    run d '.components | to_entries[]
        | select(.value.value_template != "{{ value_json.\(.key) }}"
                 or .value.unique_id != "TESTSERIAL0000_\(.key)"
                 or .value.expire_after != 960
                 or (.value.name | type) != "string")
        | .key'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "flags are problem binary sensors, everything else is a sensor" {
    [ "$(d '.components.media_read_only.platform')" = "binary_sensor" ]
    [ "$(d '.components.media_read_only.device_class')" = "problem" ]
    [ "$(d '.components.problem.platform')" = "binary_sensor" ]
    [ "$(d '.components.block_device_read_only.platform')" = "binary_sensor" ]
    [ "$(d '.components.percentage_used.platform')" = "sensor" ]
    [ "$(d '.components.self_test_status.platform')" = "sensor" ]
}

@test "entity ids are predictable" {
    [ "$(d '.components.data_written_tb.default_entity_id')" = "sensor.nvme_data_written_tb" ]
    [ "$(d '.components.media_read_only.default_entity_id')" = "binary_sensor.nvme_media_read_only" ]
}

@test "data written is a total-increasing data size in TB" {
    [ "$(d '.components.data_written_tb.unit_of_measurement')" = "TB" ]
    [ "$(d '.components.data_written_tb.device_class')" = "data_size" ]
    [ "$(d '.components.data_written_tb.state_class')" = "total_increasing" ]
    [ "$(d '.components.data_written_tb.suggested_display_precision')" = "2" ]
}

@test "temperatures are measurements in degrees Celsius" {
    for key in temperature temperature_sensor_1 temperature_sensor_2; do
        [ "$(d ".components.${key}.unit_of_measurement")" = "°C" ]
        [ "$(d ".components.${key}.device_class")" = "temperature" ]
        [ "$(d ".components.${key}.state_class")" = "measurement" ]
    done
}

@test "wear and spare are percentages" {
    [ "$(d '.components.percentage_used.unit_of_measurement')" = "%" ]
    [ "$(d '.components.available_spare.unit_of_measurement')" = "%" ]
    [ "$(d '.components.percentage_used.state_class')" = "measurement" ]
}

@test "power-on hours and busy time are durations" {
    [ "$(d '.components.power_on_hours.device_class')" = "duration" ]
    [ "$(d '.components.power_on_hours.unit_of_measurement')" = "h" ]
    [ "$(d '.components.controller_busy_time.unit_of_measurement')" = "min" ]
    [ "$(d '.components.warning_temp_time.unit_of_measurement')" = "min" ]
}

@test "low-level counters are diagnostic entities" {
    for key in host_reads host_writes critical_warning smartctl_exit_status capacity_tb; do
        [ "$(d ".components.${key}.entity_category")" = "diagnostic" ] || { echo "${key}"; false; }
    done
    [ "$(d '.components.percentage_used.entity_category')" = "null" ]
}
