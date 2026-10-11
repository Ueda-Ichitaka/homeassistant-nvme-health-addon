#!/usr/bin/env bash
# shellcheck shell=bash
# Building blocks of the NVMe Health service: host-side read-only checks and
# one poll cycle that reads the drive with smartctl and publishes Home Assistant
# MQTT discovery, state and availability messages.
#
# Callers provide mqtt_publish <topic> <payload> <retain|noretain> (usually
# mosquitto_publish), log_info <msg> and log_error <msg>. Settings come from
# these variables:
#   DEVICE                NVMe device to read (default /dev/nvme0)
#   SMARTCTL              smartctl command (default smartctl)
#   DISCOVERY_PREFIX      MQTT discovery prefix (default homeassistant)
#   INTERVAL              poll interval in seconds (default 300)
#   WARN_PERCENTAGE_USED  wear percent that raises `problem` (default 80)
#   SYSFS_ROOT            sysfs mount point (default /sys)
#   MOUNTS_FILE           mount table (default /proc/mounts)
#   DATA_MOUNT            mount point checked for read-only (default /data)
#   ADDON_VERSION         reported as discovery origin version
#   NVME_HEALTH_LIB       directory holding the jq programs
#   MQTT_HOST, MQTT_PORT, MQTT_USER, MQTT_PASSWORD  broker for mosquitto_publish

NVME_HEALTH_LIB="${NVME_HEALTH_LIB:-/usr/lib/nvme_health}"
LAST_DISCOVERY=""
# MQTT topic base of the drive seen by the last successful poll.
LAST_BASE=""

# Publishes payload $2 on topic $1 with mosquitto_pub; $3 "retain" sets the retain flag.
mosquitto_publish() {
    local args=(-h "${MQTT_HOST}" -p "${MQTT_PORT}")
    if [[ -n "${MQTT_USER:-}" ]]; then
        args+=(-u "${MQTT_USER}" -P "${MQTT_PASSWORD}")
    fi
    args+=(-t "$1" -m "$2")
    [[ "$3" == "retain" ]] && args+=(-r)
    mosquitto_pub "${args[@]}"
}

# Marks the last polled drive offline so Home Assistant shows it unavailable.
announce_offline() {
    [[ -n "${LAST_BASE}" ]] || return 0
    mqtt_publish "${LAST_BASE}/availability" "offline" retain
}

# Prints the block device name of the first namespace of an NVMe device path,
# e.g. /dev/nvme0 -> nvme0n1, /dev/nvme1n1 -> nvme1n1.
namespace_of() {
    local name
    name="$(basename "$1")"
    if [[ "${name}" =~ ^nvme[0-9]+$ ]]; then
        name="${name}n1"
    fi
    echo "${name}"
}

# Prints ON if the kernel marks block device $2 or any of its partitions
# read-only (sysfs rooted at $1), OFF if all are writable, unknown otherwise.
block_device_ro() {
    local dir="$1/block/$2" flag ro="OFF"
    [[ -r "${dir}/ro" ]] || { echo "unknown"; return; }
    for flag in "${dir}/ro" "${dir}"/"$2"*/ro; do
        [[ -r "${flag}" ]] || continue
        [[ "$(cat "${flag}")" == "1" ]] && ro="ON"
    done
    echo "${ro}"
}

# Prints ON if mount point $2 is mounted read-only according to mount table $1,
# OFF if mounted read-write, unknown if not listed or the table is unreadable.
mount_ro() {
    local options
    [[ -r "$1" ]] || { echo "unknown"; return; }
    options="$(awk -v m="$2" '$2 == m { opts = $4 } END { print opts }' "$1")"
    case ",${options}," in
        ,,) echo "unknown" ;;
        *,ro,*) echo "ON" ;;
        *) echo "OFF" ;;
    esac
}

# Prints $1 with every character outside [A-Za-z0-9_-] replaced by "_".
topic_id() {
    echo "${1//[^A-Za-z0-9_-]/_}"
}

# Reads the drive once and publishes discovery (when changed), state and
# availability. Returns non-zero without publishing if the drive cannot be read.
poll_once() {
    local device="${DEVICE:-/dev/nvme0}" smart status=0 state discovery id base

    smart="$(${SMARTCTL:-smartctl} -x --json "${device}")" || status=$?
    # Exit status bits 0 and 1: command line error or device open failed.
    if (( status & 3 )); then
        log_error "smartctl could not read ${device} (exit status ${status}): $(jq -r '[.smartctl.messages[]?.string] | join("; ")' <<< "${smart}" 2>/dev/null)"
        return 1
    fi
    if ! jq -e '.nvme_smart_health_information_log' <<< "${smart}" > /dev/null 2>&1; then
        log_error "smartctl output for ${device} has no NVMe SMART/health log"
        return 1
    fi

    state="$(jq -c \
        --arg block_ro "$(block_device_ro "${SYSFS_ROOT:-/sys}" "$(namespace_of "${device}")")" \
        --arg data_ro "$(mount_ro "${MOUNTS_FILE:-/proc/mounts}" "${DATA_MOUNT:-/data}")" \
        --argjson warn_percentage_used "${WARN_PERCENTAGE_USED:-80}" \
        -f "${NVME_HEALTH_LIB}/state.jq" <<< "${smart}")" || return 1

    id="$(topic_id "$(jq -r '.serial_number // "unknown"' <<< "${smart}")")"
    base="nvme_health/${id}"

    discovery="$(jq -c \
        --argjson state "${state}" \
        --arg version "${ADDON_VERSION:-unknown}" \
        --arg state_topic "${base}/state" \
        --arg availability_topic "${base}/availability" \
        --argjson expire_after "$(( ${INTERVAL:-300} * 3 ))" \
        -f "${NVME_HEALTH_LIB}/discovery.jq" <<< "${smart}")" || return 1

    if [[ "${discovery}" != "${LAST_DISCOVERY}" ]]; then
        mqtt_publish "${DISCOVERY_PREFIX:-homeassistant}/device/nvme_health_${id}/config" "${discovery}" retain
        LAST_DISCOVERY="${discovery}"
        log_info "Published discovery for $(jq -r '.model_name' <<< "${smart}") (${id})"
    fi
    mqtt_publish "${base}/state" "${state}" retain
    mqtt_publish "${base}/availability" "online" retain
    LAST_BASE="${base}"
}
