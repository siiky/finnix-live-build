#!/usr/bin/env bash

shasum="$1"
tee >(sha512sum -c "${shasum}" >&2)
