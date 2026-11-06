#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

TARGET_DIR=$1
shift

FSTAB="${TARGET_DIR}/etc/fstab"
OS_RELEASE="${TARGET_DIR}/etc/os-release"

function fixup_root()
{
    echo "Fixing up rootfs type: $1"

    FS_TYPE=$1
    sed -i "s#\([[:space:]]/[[:space:]]\+\)\w\+#\1${FS_TYPE}#" "$FSTAB"
}

del_part()
{
        echo "Deleting partition: $1 $2"

        SRC="$1"
        MOUNTPOINT="$2"

        # Remove old entries with same mountpoint
        sed -i "/[[:space:]]${MOUNTPOINT//\//\\\/}[[:space:]]/d" "$FSTAB"

        if [ "$SRC" != tmpfs ]; then
                # Remove old entries with same source
                sed -i "/^${SRC//\//\\\/}[[:space:]]/d" "$FSTAB"
        fi
}

function fixup_part()
{
    del_part $@

    echo "Fixing up partition: ${@//: }"

    SRC="$1"
    MOUNT="$2"
    FS_TYPE="$3"
    MOUNT_OPTS="$4"
    PASS="$5"

    # Append new entry
    echo -e "${SRC}\t${MOUNT}\t${FS_TYPE}\t${MOUNT_OPTS}\t0 $PASS" >> "$FSTAB"

    mkdir -p "${TARGET_DIR}/${MOUNT}"
}

function fixup_basic_part()
{
    echo "Fixing up basic partition: $@"

    FS_TYPE="$1"
    MOUNT="$2"
    MOUNT_OPTS="${3:-defaults}"

    fixup_part "$FS_TYPE" "$MOUNT" "$FS_TYPE" "$MOUNT_OPTS" 0
}

function partition_arg() {
    PART="$1"
    I="$2"
    DEFAULT="$3"

    ARG=$(echo $PART | cut -d':' -f"$I")
    echo ${ARG:-$DEFAULT}
}

function fixup_device_part()
{
    echo "Fixing up device partition: ${@//: }"

    DEV="$(partition_arg "$*" 1)"

    # Dev is either <name> or /dev/.../<name>
    [ "$DEV" ] || return 0
    echo $DEV | grep -qE "^/" || DEV="LABEL=$DEV"

    MOUNT="$(partition_arg "$*" 2 "/${DEV##*[/=]}")"
    FS_TYPE="$(partition_arg "$*" 3 ext4)"
    MOUNT_OPTS="$(partition_arg "$*" 4 defaults)"

    fixup_part "$DEV" "$MOUNT" "$FS_TYPE" "$MOUNT_OPTS" 2
}

function fixup_fstab()
{
    echo "Fixing up /etc/fstab..."

    fixup_root auto
    fixup_basic_part proc /proc
    fixup_basic_part devtmpfs /dev
    fixup_basic_part devpts /dev/pts mode=0620,ptmxmode=0666,gid=5
    fixup_basic_part tmpfs /dev/shm nosuid,nodev,noexec
    fixup_basic_part sysfs /sys
    fixup_basic_part debugfs /sys/kernel/debug
    fixup_basic_part pstore /sys/fs/pstore
}

function setup_login()
{
    echo "Setting TBoard login welcome and hostname..."

    install -m 0644 "$SCRIPT_DIR/overlay/etc/hostname" "$TARGET_DIR/etc/hostname"
    install -m 0644 "$SCRIPT_DIR/overlay/etc/motd" "$TARGET_DIR/etc/motd.template"
    # PAM displays the rendered banner through /run/motd.dynamic.
    # Keep the static MOTD empty so the welcome is displayed only once.
    install -m 0644 /dev/null "$TARGET_DIR/etc/motd"
    install -D -m 0755 "$SCRIPT_DIR/overlay/etc/update-motd.d/10-uname" \
        "$TARGET_DIR/etc/update-motd.d/10-uname"

    install -D -m 0644 "$SCRIPT_DIR/overlay/usr/lib/tboard/motd.py" \
        "$TARGET_DIR/usr/lib/tboard/motd.py"

    # Keep other host mappings while replacing the old local hostname.
    touch "$TARGET_DIR/etc/hosts"
    sed -i '/^[[:space:]]*127\.0\.1\.1[[:space:]]/d' "$TARGET_DIR/etc/hosts"
    printf '127.0.1.1\t%s\n' "$(cat "$TARGET_DIR/etc/hostname")" >> "$TARGET_DIR/etc/hosts"
}

function setup_ssh()
{
    echo "Setting up SSH host-key generation before service startup..."

    # Also install when mk-image.sh reuses an existing binary/ tree.
    install -D -m 0644 "$SCRIPT_DIR/overlay/etc/systemd/system/ssh.service.d/10-host-keys.conf" \
        "$TARGET_DIR/etc/systemd/system/ssh.service.d/10-host-keys.conf"
}

function setup_audio()
{
    echo "Using per-user PulseAudio sockets..."

    # Migrate reused binary/ trees without replacing other audio settings.
    if [ -f "$TARGET_DIR/etc/pulse/default.pa" ]; then
        sed -i -E 's|^[[:space:]]*load-module[[:space:]]+module-native-protocol-unix[[:space:]]+auth-anonymous=1[[:space:]]+socket=/tmp/pulse-socket[[:space:]]*$|load-module module-native-protocol-unix|' \
            "$TARGET_DIR/etc/pulse/default.pa"
    fi
    if [ -f "$TARGET_DIR/etc/pulse/client.conf" ]; then
        sed -i -E 's|^[[:space:]]*default-server[[:space:]]*=[[:space:]]*unix:/tmp/pulse-socket[[:space:]]*$|; default-server =|' \
            "$TARGET_DIR/etc/pulse/client.conf"
    fi
}

function add_build_info()
{
    [ -f "$OS_RELEASE" ] && sed -i "/^BUILD_ID=/d" "$OS_RELEASE"

    echo "Adding build-info to /etc/os-release..."
    echo "BUILD_INFO=\"$(whoami)@$(hostname) $(date)${@:+ - $@}\"" >> \
        "$OS_RELEASE"
}

echo "Executing $(basename $0)..."

setup_login
setup_ssh
setup_audio
add_build_info $@
[ -f "$FSTAB" ] && fixup_fstab

exit 0
