#!/usr/bin/env bash
set -e
disk="$1"
img="$2"
set -x
dd if="${disk}" bs=4M status=progress | tee >(sha512sum -b - >"${img}.sha512")
