#!/bin/bash

# Copyright (c) 2009-2010 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Script to update the kernel on a live running ChromiumOS instance.

# Load common constants.  This should be the first executable line.
# The path to common.sh should be relative to your script's location.

. "$(dirname $0)/common.sh"
. "$(dirname $0)/remote_access.sh"

# Script must be run inside the chroot.
restart_in_chroot_if_needed $*

DEFINE_string board "" "Override board reported by target"
DEFINE_string partition "" "Override kernel partition reported by target"
DEFINE_boolean modules false "Update modules on target"
DEFINE_boolean firmware false "Update firmware on target"

# Parse command line.
FLAGS "$@" || exit 1
eval set -- "${FLAGS_ARGV}"

# Only now can we die on error.  shflags functions leak non-zero error codes,
# so will die prematurely if 'set -e' is specified before now.
set -e

function cleanup {
  cleanup_remote_access
  rm -rf "${TMP}"
}

# Ask the target what the kernel partition is
function learn_partition() {
  [ -n "${FLAGS_partition}" ] && return
  remote_sh cat /proc/cmdline
  if echo "${REMOTE_OUT}" | grep -q "/dev/sda3"; then
    FLAGS_partition="/dev/sda2"
  else
    FLAGS_partition="/dev/sda4"
  fi
  if [ -z "${FLAGS_partition}" ]; then
    error "Partition required"
    exit 1
  fi
  info "Target reports kernel partition is ${FLAGS_partition}"
}

function main() {
  trap cleanup EXIT

  TMP=$(mktemp -d /tmp/image_to_live.XXXX)

  remote_access_init

  learn_board

  remote_sh uname -r -v

  old_kernel="${REMOTE_OUT}"

  vbutil_kernel --pack new_kern.bin \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --version 1 \
    --config ../build/images/"${FLAGS_board}"/latest/config.txt \
    --bootloader /lib64/bootstub/bootstub.efi \
    --vmlinuz /build/"${FLAGS_board}"/boot/vmlinuz

  learn_partition

  remote_cp_to new_kern.bin /tmp

  remote_sh dd if=/tmp/new_kern.bin of="${FLAGS_partition}"

  if [[ ${FLAGS_modules} -eq ${FLAGS_TRUE} ]]; then
    echo "copying modules"
    tar -C /build/"${FLAGS_board}"/lib/modules -cjf new_modules.tar .

    remote_cp_to new_modules.tar /tmp/

    remote_sh mount -o remount,rw /
    remote_sh tar -C /lib/modules -xjf /tmp/new_modules.tar
  fi

  if [[ ${FLAGS_firmware} -eq ${FLAGS_TRUE} ]]; then
    echo "copying firmware"
    tar -C /build/"${FLAGS_board}"/lib/firmware -cjf new_firmware.tar .

    remote_cp_to new_firmware.tar /tmp/

    remote_sh mount -o remount,rw /
    remote_sh tar -C /lib/firmware -xjf /tmp/new_firmware.tar
  fi

  remote_reboot

  remote_sh uname -r -v
  info "old kernel: ${old_kernel}"
  info "new kernel: ${REMOTE_OUT}"
}

main $@