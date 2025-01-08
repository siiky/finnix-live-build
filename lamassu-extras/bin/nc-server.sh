#!/usr/bin/env sh
port="$1"
nc -q 5 -w 5 -l -p "${port}"
