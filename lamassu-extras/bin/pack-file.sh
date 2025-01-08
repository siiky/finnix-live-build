#!/usr/bin/env bash
set -e
img="$1"
set -x
pv "${img}" | tee >(sha512sum -b - >"${img}.sha512") >(b3sum - >"${img}.b3") | gzip -9 | tee "${img}.gz" >(b3sum - > "${img}.gz.b3") | sha512sum -b - > "${img}.gz.sha512"
