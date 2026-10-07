#!/usr/bin/env sh
# shellcheck disable=SC3043

set -e

progname="$0"
ddextra=''
whiptail=''

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

parse_directory() {
	arg="$1"
	[ -d "${arg}" ] || return 1
	device="${arg}"
}

parse_device_or_directory() {
	# shellcheck disable=SC2310
	parse_device "$1" || parse_directory "$1"
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

# TODO Grândola support
# In the old process, the ARCA license was created after flashing, during the
# configuration step; while the new configuration screen is used on first boot,
# after flashing. However, we don't want to give OPs our ARCA activation key...
try_create_envoyrpc_license() {
	local rootfs="$1"

	if [ "${ARCA_KEY}" = '' ]; then
		cat >&2 <<EOF
WARNING: Environment variable ARCA_KEY not set, WILL NOT create EnvoyRPC
         license. You may set the ARCA_KEY environment variable and use the
         configure subcommand of this script again to create the license.
EOF
		return 0
	fi

	cat >&2 <<EOF
INFO: Will create the EnvoyRPC license in a moment. Please confirm the printed
      license has the following pattern:

LICENSE arca envoy 2 <date> uncounted hostid=<MAC address>
  _ck=<hexadecimal digits> sig="<hexadecimal digits>
  <hexadecimal digits>"
EOF

	# MAC Address
	local interface=enp2s0
	local hostid; hostid="$(sed 's|:||g;' "/sys/class/net/${interface}/address")"

	local curl_reply=''
	if ! curl_reply="$(curl 'http://license.arca.com/cgi-bin/arca_mklic' -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'Origin: http://license.arca.com' --data-raw "akey=${ARCA_KEY}&hostid=${hostid}")"; then
		echo >&2 'Failed to contact ARCA server to create a license...'
		return 1
	fi

	if echo "${curl_reply}" | grep -qiw error; then
		echo >&2 'ARCA server reply is likely an error...'
		return 1
	fi

	if ! echo "${curl_reply}" | grep -qw LICENSE; then
		echo >&2 'ARCA server reply likely does not contain the license!'
		return 1
	fi

	echo "${curl_reply}" \
	 | sed '1s/.*<pre>//; /^<\/pre>/d' \
	 | tee "${rootfs}/EnvoyRPC/htdocs/ac/license/envoyrpc.lic" >&2
}

# TODO GenMega w/ dispenser support
# See try_create_envoyrpc_license
try_set_genmega_cdu_license() {
	if [ "${platform}" != 'genmega' ]; then
		return 0
	fi

	if [ "${GENMEGA_CDU_LICENSE}" = '' ]; then
		cat >&2 <<EOF
WARNING: Environment variable GENMEGA_CDU_LICENSE not set, WILL NOT update
         'device_config.json'. You may set the GENMEGA_CDU_LICENSE environment
         variable and use the configure subcommand of this script again to
         update it.
EOF
		return 0
	fi

	local device_config="$1"
	json_setpath_inplace '"billDispenser", "license"' '"'"${GENMEGA_CDU_LICENSE}"'"' "${device_config}"
}

get_osuser() {
	case "${platform}" in
		upboard) echo 'ubilinux';;
		*) echo 'lamassu';;
	esac
}

json_setpath_inplace() {
	local path="$1"
	local value="$2"
	local file="$3"
	jq "setpath([${path}]; ${value})" "${file}" | sponge "${file}"
}

configure_root() {
	local rootfs="$1"

	set -x

	# TODO set the GenMega CDU license
	#try_set_genmega_cdu_license "${device_config}"

	# TODO install UVC quirk 0x80
	#printf 'options uvcvideo quirks=0x80\n' > "${rootfs}/etc/modprobe.d/uvcvideo.conf"

	# TODO enable EnvoyRPC systemd service
	#if [ "${model}" = 'grandola' ]; then
	#	ln -sf "${rootfs}/etc/systemd/system/envoyrpc.service" "${rootfs}/etc/systemd/system/multi-user.target.wants/envoyrpc.service"
	#	try_create_envoyrpc_license "${rootfs}"
	#fi

	set +x

	echo >&2 'Finished configuring the machine.'
}

find_partitions() {
	bootpartition=''
	rootpartition=''

	if [ ! -b "${device}" ]; then
		return 1
	fi

	for part in $(lsblk -prn -o NAME -Q 'TYPE=="part"' "${device}"); do
		case "${part}" in
			"${device}1"|"${device}p1") bootpartition="${part}";;
			"${device}2"|"${device}p2") rootpartition="${part}";;
			*);; # TODO: error out? we expect exactly 2 partitions
		esac
	done
}

configure() {
	settraps

	# TODO Re-enable configuration?
	#local should_unmount=''
	#if [ -b "${device}" ]; then
	#	# If device is a block device, mount ${device}*2 into ${rootfs}
	#	find_partitions
	#	local rootfs="/mnt/${rootpartition}"
	#	mkdir -p "${rootfs}"
	#	mount -t ext4 "${rootpartition}" "${rootfs}"
	#	should_unmount=yes
	#elif [ -d "${device}" ]; then
	#	# If it's a directory, just use it instead
	#	rootfs="${device}"
	#else
	#	echo >&2 "Unexpected error: '${device}' is neither a block device nor a directory!"
	#	exit 1
	#fi

	#configure_root "${rootfs}"
	#if [ "${should_unmount}" = 'yes' ]; then
	#	umount "${rootfs}"
	#fi
}

flash_image() {
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

gpt_verify_disk() {
	sgdisk -v "$1"
}

gpt_fix_partitions() {
	# move GPT partition to end
	sgdisk -e "${device}"

	# resize partition to use all space available in disk
	#  -d 2  deletes the partition 2
	#  -n 2:0:0  recreates partition 2, using the default start/end values -- start is the same as the old partition; end is the maximum available
	sgdisk -d 2 -n 2:0:0 "${device}"
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

	fsck -V -f -y "${rootpartition}"
	case $? in
		0|1) ;;
		*) exit $?;;
	esac

	e2fsck -v -f -y "${rootpartition}"
	case $? in
		0|1) ;;
		*) exit $?;;
	esac

	set -e

	# resize filesystem to use all space available in the partition
	resize2fs "${rootpartition}"

	gpt_verify_disk "${device}"

	set +x

	echo >&2 'The image has been successfully installed. It is safe to reboot the machine now, even if the configuration step fails.'
}

# device image machine printer
install() {
	settraps
	flash
	configure
	echo >&2
	echo >&2 'All went well, please reboot now.'
}

set_image() {
	# shellcheck disable=SC2154
	#image_release_number="${LMX_RELEASE_NUMBER}"
	#image_machine_version="${LMX_MACHINE_VERSION}"
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
		'install' 'Install a Lamassu machine (i.e., flash and configure)' #\
		#'configure' 'Configure an already-installed Lamassu machine'
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

tui_input_arca_key() {
	tui --title 'ARCA key' --clear \
		--inputbox 'Please type in your ARCA key.' 0 0
}

tui_input_genmega_cdu_license() {
	tui --title 'GenMega CDU license' --clear \
		--inputbox 'Please type in your GenMega CDU license.

If your machine is one-way, you may leave it empty.' 0 0
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

	local arca_key_line=''
	if [ "${ARCA_KEY}" != '' ]; then
		arca_key_line="ARCA key: ${ARCA_KEY}\n"
	fi

	local gm_cdu_line=''
	if [ "${GENMEGA_CDU_LICENSE}" != '' ]; then
		gm_cdu_line="GenMega CDU license: ${GENMEGA_CDU_LICENSE}\n"
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

${arca_key_line}\
${gm_cdu_line}\
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

guided_input_arca_key() {
	if [ "${model}" = 'grandola' ]; then
		ARCA_KEY="$(tui_input_arca_key)"
		handle_tui_return $?
	fi
}

guided_input_genmega_cdu_license() {
	if [ "${platform}" = 'genmega' ]; then
		GENMEGA_CDU_LICENSE="$(tui_input_genmega_cdu_license)"
		handle_tui_return $?
	fi
}

guided_confirmation() {
	tui_confirmation
	handle_tui_return $?
}

guided_configure() {
	guided_pick_device
	#guided_input_arca_key
	#guided_input_genmega_cdu_license

	# shellcheck disable=SC2310
	if guided_confirmation; then
		configure
	fi
}

guided_install() {
	guided_pick_device
	#guided_input_arca_key
	#guided_input_genmega_cdu_license

	set_image

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
