#!/usr/bin/env bash

imggz="$1"
imggzsha512="$2"
imgsha512="$3"

sha512sum_pipe() {
	local shasum="$1"
	tee >(sha512sum -c "${shasum}" >&2)
}

sha512sum_pipe "${imggzsha512}" < "${imggz}" | gunzip -9 | sha512sum_pipe "${imgsha512}"
