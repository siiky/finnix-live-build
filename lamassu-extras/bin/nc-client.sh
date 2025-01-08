#!/usr/bin/env sh
ip="$1"
port="$2"
nc -q 5 -w 5 "${ip}" "${port}"
