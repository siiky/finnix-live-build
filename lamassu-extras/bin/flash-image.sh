#!/usr/bin/env sh
# shellcheck disable=SC3043

set -e

progname="$0"
ddextra=''
whiptail=''
use_bmap='no'

device='DEVICE'
image='IMAGE'
image_release_number=''
image_machine_version=''

usage() {
	cat >&2 <<EOF
usage: ${progname} SUBCOMMAND

Where SUBCOMMAND is one of the following:

	guided: interactive TUI to choose what to do.
	install: flash an image.

EOF
	exit 1
}

usage_install() {
	cat >&2 <<EOF
usage: ${progname} install ${device} ${image}

If this is an UP board, DEVICE is likely /dev/mmcblk0.
IMAGE is an image (uncompressed ISO/WIC, gzip, zstd, lzip, or xz) or - to read from stdin.

WARNING: Be sure to specify the correct DEVICE, it will be overwritten!

EXAMPLES:
To install an uncompressed WIC image file:
	${progname} install /dev/mmcblk0 image.wic

To install a gzipped WIC image file:
	${progname} install /dev/mmcblk0 image.wic.gz

EOF
	exit 1
}

usage_guided() {
	cat >&2 <<EOF
usage: ${progname} guided ${image}

This subcommand presents the user with an interactive menu that they can follow, as an alternative to the other subcommands.

IMAGE is an image file (uncompressed ISO/WIC, gzip, zstd, lzip, or xz).

EOF
	exit 1
}

parse_device() {
	arg="$1"
	[ -b "${arg}" ] || return 1
	device="${arg}"
}

parse_image_stdin() {
	if [ "$1" != '-' ]; then return 1; fi
	image="$1"
}

parse_image_file() {
	if [ ! -f "$1" ]; then return 1; fi
	image="$1"
}

parse_image() {
	# shellcheck disable=SC2310
	parse_image_file "$@" || parse_image_stdin "$@"
}

# DEVICE IMAGE
parse_args_install() {
	device='DEVICE'
	# shellcheck disable=SC2310
	parse_device "$1" && shift \
		&& parse_image "$1"
}

# IMAGE
parse_args_guided() {
	parse_image "$1"
}

settraps() {
	# shellcheck disable=SC2154
	trap 'retcode="$?"
		if [ "${retcode}" -eq 0 ]; then
			echo >&2 "All went well, please reboot now."
		else
			echo >&2 "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n!!! Something went wrong, DO NOT REBOOT !!!\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\nIf possible go over the process again, or contact support."
		fi
		read -p "Press ENTER to ackowledge." ignored
		exit "${retcode}"' \
		INT TERM EXIT
}

find_partitions() {
	bootpartition=''
	rootapartition=''
	rootbpartition=''
	datapartition=''

	if [ ! -b "${device}" ]; then
		return 1
	fi

	for part in $(lsblk -prn -o NAME -Q 'TYPE=="part"' "${device}"); do
		case "${part}" in
			"${device}1"|"${device}p1") bootpartition="${part}";;
			"${device}2"|"${device}p2") rootapartition="${part}";;
			"${device}3"|"${device}p3") rootbpartition="${part}";;
			"${device}4"|"${device}p4") datapartition="${part}";;
			*);; # TODO: error out? we expect exactly 2 partitions
		esac
	done
}

flash_image_bmap() {
	bmaptool copy "${image}" "${device}"
}

flash_image_dd() {
	if [ "${image}" = '-' ]; then
		set -x
		# shellcheck disable=SC2086
		dd of="${device}" bs=4M ${ddextra}
	else
		set -x
		case "$(file --brief --mime-type "${image}")" in
			application/gzip)
				# shellcheck disable=SC2086
				zcat "${image}" | dd of="${device}" bs=4M ${ddextra};;
			application/x-lz4)
				# shellcheck disable=SC2086
				lz4cat "${image}" | dd of="${device}" bs=4M ${ddextra};;
			application/zstd)
				# shellcheck disable=SC2086
				zstdcat "${image}" | dd of="${device}" bs=4M ${ddextra};;
			application/x-lzip)
				# shellcheck disable=SC2086
				lzip -cd "${image}" | dd of="${device}" bs=4M ${ddextra};;
			application/x-xz)
				# shellcheck disable=SC2086
				xzcat "${image}" | dd of="${device}" bs=4M ${ddextra};;
			application/x-iso9660-image|application/octet-stream|*)
				# shellcheck disable=SC2086
				dd if="${image}" of="${device}" bs=4M ${ddextra};;
		esac
	fi
}

flash_image() {
	if [ "${use_bmap}" = 'yes' ]; then
		flash_image_bmap || flash_image_dd
	else
		flash_image_dd
	fi
}

gpt_verify_disk() {
	sgdisk -v "$1"
}

gpt_fix_partitions() {
	# move GPT partition to end
	sgdisk -e "${device}"

	# resize data partition to use all remaining space available in disk
	#  -d 4  deletes the partition 4
	#  -n 4:0:0  recreates partition 4, using the default start/end values -- start is the same as the old partition; end is the maximum available
	#  -c 4:ssuos-data  name this partition ssuos-data
	sgdisk -d 4 -n 4:0:0 -c 4:ssuos-data "${device}"
}

fix_ext4_partition() {
	local partition="$1"
	set +e
	fsck -V -f -y "${partition}"
	case $? in
		0|1) ;;
		*) exit $?;;
	esac

	e2fsck -v -f -y "${partition}"
	case $? in
		0|1) ;;
		*) exit $?;;
	esac
	set -e

	# resize filesystem to use all space available in the partition
	resize2fs "${partition}"
}

flash() {
	cat >&2 <<EOF

WARNING! DO NOT REBOOT THE MACHINE UNLESS THE IMAGE IS SUCCESSFULLY FLASHED!

At the end of this process a message will inform you that it has successfully finished.
If the script exits and you do not see that message, please contact our support.
EOF

	## Write image to disk
	flash_image

	## Fix things up

	gpt_verify_disk "${device}"

	gpt_fix_partitions "${device}"

	partprobe "${device}"

	find_partitions

	set +e # temporarily disable exit on non-0

	fsck -V -f -y "${bootpartition}"
	case $? in
		0|1) ;;
		*) exit $?;;
	esac

	set -e

	for partition in "${rootapartition}" "${rootbpartition}" "${datapartition}"; do
		fix_ext4_partition "${partition}"
	done

	gpt_verify_disk "${device}"

	set +x

	echo >&2 'The image has been successfully installed. It is safe to reboot the machine now, even if the configuration step fails.'
}

install() {
	settraps
	flash
	echo >&2
	echo >&2 'All went well, please reboot now.'
}

tui() {
	"${whiptail}" "$@" 3>&2 2>&1 1>&3 3>&-
}

handle_tui_return() {
	tui_return=$1

	local OK=0
	local CANCEL=1
	local ESC=255

	case "${tui_return}" in
		"${OK}");;
		"${CANCEL}"|"${ESC}") exit 0;;
		*) exit "${tui_return}";;
	esac
}

tui_subcmd() {
	local menumsg='Choose what operation to perform.'
	if [ "${image_release_number}" != '' ]; then menumsg="${menumsg}\nImage release number: ${image_release_number}"; fi
	if [ "${image_machine_version}" != '' ]; then menumsg="${menumsg}\nLamassu machine version: ${image_machine_version}"; fi
	tui --title 'What do you wish to do?' --clear \
		--menu "${menumsg}" 0 0 0 \
		'install' 'Install a Lamassu machine' #\
}

tui_device() {
	# shellcheck disable=SC2016
	local awkscript='\
{ disks[$1] = 1; }
$2 != "" { mounted[$1] = 1 }
END {
	for (disk in disks) {
		if (!mounted[disk]) {
			printf("%s\n", disk)
		}
	}
}'

	local disks; disks="$(lsblk -prn -o NAME -Q 'TYPE=="disk"' | grep -vw -e 'fd[0-9]\+' -e 'zram[0-9]\+')"
	local unmounted_disks; unmounted_disks="$(for disk in ${disks}; do printf '%s %s\n' "${disk}" ''; lsblk -prn -o PKNAME,MOUNTPOINT -Q 'TYPE=="part"' "${disk}"; done | sed 's| |\t|;' | awk -F'	' "${awkscript}")"
	if [ -z "${unmounted_disks}" ]; then
		tui_msgbox 'No disks found!' 'No disks available for install were found. If you are installing a non-Lamassu machine, make sure the internal drive(s) to which you want to install are well connected. If you need help, please contact the Lamassu support.'
		return 1
	fi

	local entries; entries="$(for disk in ${unmounted_disks}; do echo "${disk} ${disk}"; done)"
	# shellcheck disable=SC2086
	tui --title "To which device do you wish to ${subcmd}?" --clear \
		--notags \
		--menu 'Choose which device to operate on.\nWARNING: Be sure to choose the correct device. Data will be lost!' 0 0 0 \
		${entries}
}

tui_confirmation() {
	local image_file_line=''
	if [ "${image}" != 'IMAGE' ]; then
		image_file_line="Image: ${image}\n"
	fi

	local image_release_number_line=''
	if [ "${image_release_number}" != '' ]; then
		image_release_number_line="Image release number: ${image_release_number}\n"
	fi

	local image_machine_version_line=''
	if [ "${image_machine_version}" != '' ]; then
		image_machine_version_line="Lamassu machine version: ${image_machine_version}\n"
	fi

	tui --title 'Do you wish to proceed?' --clear \
		--yes-button "Yes, ${subcmd}" --defaultno \
		--yesno "\
Do you wish to proceed and ${subcmd} as described below?

WARNING: Data on this drive will be lost! Only proceed if certain.

${image_file_line}\
Device: ${device}
${image_release_number_line}\
${image_machine_version_line}\
" 0 0
}

tui_msgbox() {
	local title="$1"
	local text="$2"
	tui --title "${title}" --clear --msgbox "${text}" 0 0
}

guided_pick_device() {
	device="$(tui_device)"
	handle_tui_return $?
}

guided_confirmation() {
	tui_confirmation
	handle_tui_return $?
}

guided_install() {
	guided_pick_device

	# shellcheck disable=SC2310
	if guided_confirmation; then
		install
	fi
}

guided_pick_subcmd() {
	subcmd="$(tui_subcmd)"
	handle_tui_return $?
}

# no arguments
guided() {
	for alt in whiptail dialog; do
		if command -v -- "${alt}" >/dev/null; then
			whiptail="${alt}"
			break
		fi
	done
	if [ "${whiptail}" = '' ]; then
		echo >&2 'No whiptail-like command found'
		exit 1
	fi

	set +x
	guided_pick_subcmd
	"guided_${subcmd}"
	set -x
}

prepare_alpine() {
	apk add sgdisk
}

prepare_debian_like() {
	# Stop automounting disks
	systemctl stop udisks2.service

	# Show dd's progress stats
	ddextra='status=progress conv=fsync'
}

prepare() {
	local os=unknown
	if [ -f /etc/os-release ]; then
		os="$(grep '^ID=' /etc/os-release | cut -f2 -d=)"
	fi
	case "${os}" in
		alpine) prepare_alpine;;
		debian|ubuntu|linuxmint|'"finnix"') prepare_debian_like;;
		*) echo >&2 'OS is unknown. Will proceed but unexpected results may occur!';;
	esac

	# Check if bmaptool exists
	if command -v -- bmaptool >/dev/null; then
		use_bmap='yes'
	fi
}

subcmd="$1"
case "${subcmd}" in
	install|guided)
		shift 1
		"parse_args_${subcmd}" "$@" || "usage_${subcmd}"
		set -x
		prepare
		"${subcmd}";;
	*) usage;;
esac
