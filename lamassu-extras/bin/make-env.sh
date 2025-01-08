#!/usr/bin/env sh
lmx_release="$1"
lm_version="$2"

cat <<EOF
LMX_RELEASE_NUMBER=${lmx_release}
LMX_MACHINE_VERSION=${lm_version}
EOF
