#!/usr/bin/env bats
# Tests for functions.sh: host checks (sysfs read-only flags, /data mount) and
# one poll cycle (smartctl -> state/discovery -> MQTT), with smartctl and the
# MQTT publisher replaced by fakes.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../nvme_health/rootfs/usr/lib/nvme_health"
    FIX="${BATS_TEST_DIRNAME}/fixtures"
    export NVME_HEALTH_LIB="${LIB}"
    # shellcheck source=../nvme_health/rootfs/usr/lib/nvme_health/functions.sh
    source "${LIB}/functions.sh"

    SYS="${BATS_TEST_TMPDIR}/sys"
    mkdir -p "${SYS}/block/nvme0n1/nvme0n1p1" "${SYS}/block/nvme0n1/nvme0n1p8"
    echo 0 > "${SYS}/block/nvme0n1/ro"
    echo 0 > "${SYS}/block/nvme0n1/nvme0n1p1/ro"
    echo 0 > "${SYS}/block/nvme0n1/nvme0n1p8/ro"

    PUBLISHED="${BATS_TEST_TMPDIR}/published"
    : > "${PUBLISHED}"
    LOGGED="${BATS_TEST_TMPDIR}/logged"
    : > "${LOGGED}"

    SYSFS_ROOT="${SYS}"
    MOUNTS_FILE="${BATS_TEST_TMPDIR}/no-such-mounts"
    ADDON_VERSION="0.0.0-test"
}

# Fakes used by poll_once.
mqtt_publish() { printf '%s\t%s\t%s\n' "$1" "$3" "$2" >> "${PUBLISHED}"; }
log_info() { echo "INFO $*" >> "${LOGGED}"; }
log_error() { echo "ERROR $*" >> "${LOGGED}"; }
fake_smartctl() { # fixture exit_status
    cat "${FIX}/$1"
    return "$2"
}

# Prints the payload published on topic $1.
payload_on() {
    awk -F'\t' -v t="$1" '$1 == t { print $3 }' "${PUBLISHED}"
}

@test "namespace_of maps a controller to its first namespace" {
    [ "$(namespace_of /dev/nvme0)" = "nvme0n1" ]
    [ "$(namespace_of /dev/nvme1n1)" = "nvme1n1" ]
}

@test "block_device_ro is OFF when disk and partitions are writable" {
    [ "$(block_device_ro "${SYS}" nvme0n1)" = "OFF" ]
}

@test "block_device_ro is ON when the disk is read-only" {
    echo 1 > "${SYS}/block/nvme0n1/ro"
    [ "$(block_device_ro "${SYS}" nvme0n1)" = "ON" ]
}

@test "block_device_ro is ON when any partition is read-only" {
    echo 1 > "${SYS}/block/nvme0n1/nvme0n1p8/ro"
    [ "$(block_device_ro "${SYS}" nvme0n1)" = "ON" ]
}

@test "block_device_ro is unknown when sysfs has no such device" {
    [ "$(block_device_ro "${SYS}" nvme9n1)" = "unknown" ]
}

@test "mount_ro reads the mount options of a mount point" {
    mounts="${BATS_TEST_TMPDIR}/mounts"
    cat > "${mounts}" <<'EOF'
overlay / overlay rw,relatime 0 0
/dev/nvme0n1p8 /data ext4 rw,relatime,commit=30 0 0
/dev/nvme0n1p8 /ssl ext4 ro,relatime 0 0
EOF
    [ "$(mount_ro "${mounts}" /data)" = "OFF" ]
    [ "$(mount_ro "${mounts}" /ssl)" = "ON" ]
    [ "$(mount_ro "${mounts}" /share)" = "unknown" ]
}

@test "topic_id keeps only characters valid in MQTT discovery ids" {
    [ "$(topic_id 'AB 12/x+#Y')" = "AB_12_x__Y" ]
}

@test "poll_once publishes retained discovery, state and online availability" {
    SMARTCTL="fake_smartctl smartctl_nvme0.json 0"
    poll_once
    [ "$(payload_on homeassistant/device/nvme_health_TESTSERIAL0000/config | jq -r .device.model)" = "Lexar SSD NQ790 2TB" ]
    [ "$(payload_on nvme_health/TESTSERIAL0000/state | jq -r .percentage_used)" = "1" ]
    [ "$(payload_on nvme_health/TESTSERIAL0000/availability)" = "online" ]
    [ "$(awk -F'\t' '$2 != "retain"' "${PUBLISHED}")" = "" ]
}

@test "poll_once publishes discovery only when it changes" {
    SMARTCTL="fake_smartctl smartctl_nvme0.json 0"
    poll_once
    poll_once
    [ "$(awk -F'\t' '$1 ~ /\/config$/' "${PUBLISHED}" | wc -l)" -eq 1 ]
    [ "$(awk -F'\t' '$1 ~ /\/state$/' "${PUBLISHED}" | wc -l)" -eq 2 ]
}

@test "poll_once passes the host checks and wear limit into the state" {
    SMARTCTL="fake_smartctl smartctl_nvme0.json 0"
    echo 1 > "${SYS}/block/nvme0n1/ro"
    poll_once
    [ "$(payload_on nvme_health/TESTSERIAL0000/state | jq -r .block_device_read_only)" = "ON" ]
    [ "$(payload_on nvme_health/TESTSERIAL0000/state | jq -r .data_partition_read_only)" = "null" ]
    [ "$(payload_on nvme_health/TESTSERIAL0000/state | jq -r .problem)" = "ON" ]
}

@test "poll_once keeps publishing when smartctl only reports drive warnings" {
    # Exit status bit 3 (DISK FAILING) still comes with a full health log.
    SMARTCTL="fake_smartctl smartctl_nvme0.json 8"
    poll_once
    [ "$(payload_on nvme_health/TESTSERIAL0000/state | jq -r .percentage_used)" = "1" ]
}

@test "poll_once fails and publishes nothing when the device cannot be opened" {
    SMARTCTL="fake_smartctl smartctl_nvme0.json 2"
    run poll_once
    [ "$status" -ne 0 ]
    [ "$(cat "${PUBLISHED}")" = "" ]
    grep -q "ERROR" "${LOGGED}"
}

@test "poll_once fails when smartctl output has no NVMe health log" {
    no_log() { echo '{"smartctl": {"exit_status": 0}}'; }
    SMARTCTL="no_log"
    run poll_once
    [ "$status" -ne 0 ]
    [ "$(cat "${PUBLISHED}")" = "" ]
}

@test "announce_offline publishes retained offline for the polled drive" {
    SMARTCTL="fake_smartctl smartctl_nvme0.json 0"
    poll_once
    : > "${PUBLISHED}"
    announce_offline
    [ "$(cat "${PUBLISHED}")" = "$(printf 'nvme_health/TESTSERIAL0000/availability\tretain\toffline')" ]
}

@test "announce_offline does nothing before the first successful poll" {
    announce_offline
    [ "$(cat "${PUBLISHED}")" = "" ]
}

@test "mosquitto_publish passes broker, credentials and retain flag to mosquitto_pub" {
    unset -f mqtt_publish
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/mosquitto_pub" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${BATS_TEST_TMPDIR}/args"
FAKE
    chmod +x "${BATS_TEST_TMPDIR}/bin/mosquitto_pub"
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    MQTT_HOST=core-mosquitto MQTT_PORT=1883 MQTT_USER=addons MQTT_PASSWORD=secret

    mosquitto_publish some/topic '{"a":1}' retain
    [ "$(tr '\n' ' ' < "${BATS_TEST_TMPDIR}/args")" = "-h core-mosquitto -p 1883 -u addons -P secret -t some/topic -m {\"a\":1} -r " ]

    mosquitto_publish some/topic hello noretain
    [ "$(tr '\n' ' ' < "${BATS_TEST_TMPDIR}/args")" = "-h core-mosquitto -p 1883 -u addons -P secret -t some/topic -m hello " ]
}

@test "mosquitto_publish omits credentials when no user is set" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/mosquitto_pub" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${BATS_TEST_TMPDIR}/args"
FAKE
    chmod +x "${BATS_TEST_TMPDIR}/bin/mosquitto_pub"
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    MQTT_HOST=broker MQTT_PORT=1883 MQTT_USER="" MQTT_PASSWORD=""

    mosquitto_publish t m retain
    [ "$(tr '\n' ' ' < "${BATS_TEST_TMPDIR}/args")" = "-h broker -p 1883 -t t -m m -r " ]
}
