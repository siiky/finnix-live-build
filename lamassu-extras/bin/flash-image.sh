#!/usr/bin/env sh
# shellcheck disable=SC3043

set -e

progname="$0"
ddextra=''
whiptail=''

device='DEVICE'
platform='PLATFORM'
model='MODEL'
printer='PRINTER'
image='IMAGE'

usage() {
	cat >&2 <<EOF
usage: ${progname} SUBCOMMAND

Where SUBCOMMAND is one of the following:

	guided: interactive TUI to choose what to do.
	install: flash an image and configure it afterwards.
	configure: configure an image that's already installed.

EOF
	exit 1
}

usage_configure() {
	cat >&2 <<EOF
usage: ${progname} configure ${device} ${platform} ${model} [${printer}]

ROOT may be either the (unmounted) DEVICE, or the mount DIRECTORY of the root partition. If this is an UP or UP4000, DEVICE is likely /dev/mmcblk0.
PLATFORM is the model of the board (for Lamassu machines), or of the maker (for non-Lamassu machines): up4000, upboard, coincloud, generalbytes, genmega.
MODEL is the model of the machine: aveiro, gaia, grandola, tejo, sintra, jcm-ipro-rc, mei-bnr, mei-scr, gemini, gmuk1, gmuk2, wallkiosk, batm3, batm7in.
PRINTER (optional; defaults to none) is the model of the printer: nippon, zebra, genmega, none.

WARNING: Be sure to specify the correct DEVICE!

EXAMPLES:
To configure an already-installed machine:
	${progname} configure /dev/mmcblk0 upboard tejo nippon

EOF
	exit 1
}

usage_install() {
	cat >&2 <<EOF
usage: ${progname} install ${device} ${image} ${platform} ${model} [${printer}]

If this is an UP board, DEVICE is likely /dev/mmcblk0.
IMAGE is an image (uncompressed, gzipped, or xzipped) or - to read from stdin.

PLATFORM is the model of the board (for Lamassu machines), or of the maker (for non-Lamassu machines): up4000, upboard, coincloud, generalbytes, genmega.
MODEL is the model of the machine: aveiro, gaia, grandola, tejo, sintra, jcm-ipro-rc, mei-bnr, mei-scr, gemini, gmuk1, gmuk2, wallkiosk, batm3, batm7in.
PRINTER (optional; defaults to none) is the model of the printer: nippon, zebra, genmega, none.

WARNING: Be sure to specify the correct DEVICE, it will be overwritten!

EXAMPLES:
To install an uncompressed image file:
	${progname} install /dev/mmcblk0 image.img up4000 tejo nippon

To install a gzipped image file:
	${progname} install /dev/mmcblk0 image.img.gz up4000 tejo nippon

EOF
	exit 1
}

usage_guided() {
	cat >&2 <<EOF
usage: ${progname} guided ${image}

This subcommand presents the user with an interactive menu that they can follow, as an alternative to the other subcommands.

IMAGE is an image (uncompressed, gzipped, or xzipped) file.

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
	parse_device "$1" || parse_directory "$1"
}

parse_platform() {
	arg="$1"
	case "${arg}" in
		up4000|upboard);; # Board name, for Lamassu machines
		coincloud|genmega|generalbytes);; # Maker name, for non-Lamassu machines
		*) return 1;;
	esac
	platform="${arg}"
}

parse_model() {
	arg="$1"
	case "${platform}" in
		up4000|upboard)
			case "${arg}" in
				aveiro|gaia|grandola|tejo|sintra);;
				*) return 1;;
			esac;;
		coincloud)
			case "${arg}" in
				jcm-ipro-rc|mei-bnr|mei-scr);;
				*) return 1;;
			esac;;
		genmega)
			case "${arg}" in
				gemini|gmuk1|gmuk2|wallkiosk);;
				*) return 1;;
			esac;;
		generalbytes)
			case "${arg}" in
				batm3|batm7in);;
				*) return 1;;
			esac;;
		*) return 1;;
	esac
	model="${arg}"
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
	parse_image_file "$@" || parse_image_stdin "$@"
}

parse_printer() {
	case "$1" in
		nippon) printer='Nippon-2511D-2';;
		zebra) printer='Zebra-KR-403';;
		genmega) printer=genmega;;
		none) printer=None;;
		"") printer=None;;
		*) return 1;;
	esac
}

# ROOT PLATFORM MODEL [PRINTER]
parse_args_configure() {
	device='ROOT'
	parse_device_or_directory "$1" \
		&& parse_platform "$2" \
		&& parse_model "$3" \
		&& parse_printer "$4"
}

# DEVICE IMAGE PLATFORM MODEL [PRINTER]
parse_args_install() {
	device='DEVICE'
	parse_device "$1" \
		&& parse_image "$2" \
		&& parse_platform "$3" \
		&& parse_model "$4" \
		&& parse_printer "$5"
}

# IMAGE
parse_args_guided() {
	parse_image_file "$1"
}

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

	curl 'http://license.arca.com/cgi-bin/arca_mklic' \
	 -X POST \
	 -H 'Content-Type: application/x-www-form-urlencoded' \
	 -H 'Origin: http://license.arca.com' \
	 --data-raw "akey=${ARCA_KEY}&hostid=${hostid}" \
	 | sed '1s/.*<pre>//; /^<\/pre>/d' \
	 | tee "${rootfs}/EnvoyRPC/htdocs/ac/license/envoyrpc.lic" >&2
}

try_set_genmega_cdu_license() {
	if [ "${GENMEGA_CDU_LICENSE}" = '' ]; then
		cat >&2 <<EOF
WARNING: Environment variable GENMEGA_CDU_LICENSE not set, WILL NOT update
         'device_config.json'. You may set the GENMEGA_CDU_LICENSE environment
         variable and use the configure subcommand of this script again to
         update it.
EOF
		return 0
	fi

	local lmroot="$1"
	sed -i '/^    "license"/s/"",$/"'"${GENMEGA_CDU_LICENSE}"'",/;' "${lmroot}/device_config.json"
}

configure_root() {
	local rootfs="$1"

	set -x
	# copy machine-specific configs
	local lmroot="${rootfs}/opt/lamassu-machine"
	cp "${lmroot}/hardware/codebase/${platform}/${model}/device_config.json" "${lmroot}/"

	# set the correct printer
	sed -i 's/Nippon-2511D-2/'"${printer}"'/g' "${lmroot}/device_config.json"

	# set the GenMega CDU license
	if [ "${platform}" = 'genmega' ]; then
		try_set_genmega_cdu_license "${lmroot}"
	fi

	# copy model-specific supervisor configs
	rm -rf "${rootfs}/etc/supervisor/conf.d/"
	cp -r "${lmroot}/hardware/system/${platform}/${model}/supervisor/conf.d/" -t "${rootfs}/etc/supervisor/"

	# copy model-specific udev rules
	rm -f "${rootfs}"/etc/udev/rules.d/99-*.rules
	cp -r "${lmroot}/hardware/system/${platform}/${model}"/udev/* -t "${rootfs}/etc/udev/rules.d/"

	# enable EnvoyRPC systemd service
	if [ "${model}" = 'grandola' ]; then
		ln -sf "${rootfs}/etc/systemd/system/envoyrpc.service" "${rootfs}/etc/systemd/system/multi-user.target.wants/envoyrpc.service"
		try_create_envoyrpc_license "${rootfs}"
	fi

	# copy calibrate-screen.sh
	if [ -f "${lmroot}/hardware/system/${platform}/${model}/calibrate-screen.sh" ]; then
		cp "${lmroot}/hardware/system/${platform}/${model}/calibrate-screen.sh" "${rootfs}/opt/calibrate-screen.sh"
	else
		echo "#!/usr/bin/env sh" > "${rootfs}/opt/calibrate-screen.sh"
	fi
	chmod 0755 "${rootfs}/opt/calibrate-screen.sh"

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
	prepare

	if [ -b "${device}" ]; then
		# If device is a block device, mount ${device}*2 into ${rootfs}
		find_partitions
		local rootfs="/mnt/${rootpartition}"
		mkdir -p "${rootfs}"
		mount -t ext4 "${rootpartition}" "${rootfs}"
	elif [ -d "${device}" ]; then
		# If it's a directory, just use it instead
		rootfs="${device}"
	else
		echo >&2 "Unexpected error: '${device}' is neither a block device nor a directory!"
		exit 1
	fi

	configure_root "${rootfs}"
	#[ -b "${device}" ] && umount "${rootfs}"
}

flash_image() {
	# Start by assuming stdin
	ddif=''
	decompresscmd=''

	if [ "${image}" != '-' ]; then
		case "$(file --brief --mime-type "${image}")" in
			application/gzip) decompresscmd="zcat ${image}";;
			application/x-xz) decompresscmd="xzcat ${image}";;
			*) ddif="if=${image}";;
		esac
	fi

	if [ "${ddif}" = '' ]; then
		set -x
		# shellcheck disable=SC2086
		${decompresscmd} | dd of="${device}" bs=4M ${ddextra}
	else
		set -x
		# shellcheck disable=SC2086
		dd ${ddif} of="${device}" bs=4M ${ddextra}
	fi
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

	# verify
	sgdisk -v "${device}"

	# move GPT partition to end
	sgdisk -e "${device}"

	# resize partition to use all space available in disk
	#  -d 2  deletes the partition 2
	#  -n 2:0:0  recreates partition 2, using the default start/end values -- start is the same as the old partition; end is the maximum available
	sgdisk -d 2 -n 2:0:0 "${device}"

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

	sgdisk -v "${device}"

	set +x

	echo >&2 'The image has been successfully installed. It is safe to reboot the machine now, even if the configuration step fails.'
}

# device image machine printer
install() {
	prepare
	flash
	configure
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
		"$OK");;
		"$CANCEL"|"$ESC") exit 0;;
		*) exit "${tui_return}";;
	esac
}

tui_subcmd() {
	tui --title 'What do you wish to do?' --clear \
		--menu 'Choose what operation to perform' 0 0 0 \
		'install' 'Install a Lamassu machine (i.e., flash and configure)' \
		'configure' 'Configure an already-installed Lamassu machine'
}

tui_device() {
	local disks; disks="$(lsblk -prn -o NAME -Q 'TYPE=="disk"')"
	local entries; entries="$(for disk in ${disks}; do echo "${disk} ${disk}"; done)"
	# shellcheck disable=SC2086
	tui --title "To which device do you wish to ${subcmd}?" --clear \
		--notags \
		--menu 'Choose which device to operate on.\nWARNING: Be sure to choose the correct device. Data will be lost!' 0 0 0 \
		${entries}
}

tui_platform() {
	tui --title 'Choose a platform/maker' --clear \
		--menu 'Choose the platform/maker of your machine' 0 0 0 \
		up4000 'Lamassu machine with Aaeon UP4000 board' \
		upboard 'Lamassu machine with Aaeon UP board' \
		coincloud 'CoinCloud machine' \
		generalbytes 'General Bytes machine' \
		genmega 'GenMega machine'
}

tui_model_() {
	tui --title 'Choose a model' --clear --notags \
		--menu 'Choose the model of your machine' 0 0 0 \
		"$@"
}

tui_model() {
	case "${platform}" in
		up4000|upboard) tui_model_ \
			aveiro 'Aveiro' \
			gaia 'Gaia' \
			grandola 'Grândola' \
			tejo 'Tejo' \
			sintra 'Sintra' \
			;;

		coincloud) tui_model_ \
			jcm-ipro-rc 'JCM iPro RC' \
			mei-bnr 'MEI BNR' \
			mei-scr 'MEI SCR' \
			;;

		genmega) tui_model_ \
			gmuk1 'Universal Kiosk 1' \
			gmuk2 'Universal Kiosk 2' \
			gemini 'Gemini' \
			wallkiosk 'Wall Kiosk' \
			;;

		generalbytes) tui_model_ \
			batm7in 'BATM Two (7" screen)' \
			batm3 'BATM Three' \
			;;

		*)
			echo >&2 "Unknown/Unsupported platform ${platform}"
			exit 1;;
	esac
}

tui_printer() {
	local entries=''
	if [ "${platform}" = 'genmega' ]; then
		entries='genmega genmega'
	else
		entries='nippon Nippon-2511D-2 zebra Zebra-KR-403'
	fi
	# shellcheck disable=SC2086
	tui --title 'Choose a printer model' --clear \
		--menu 'Select the model of printer your machine features, if any.' 0 0 0 \
		none 'None' \
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

Image: ${image}
Device: ${device}
Platform: ${platform}
Model: ${model}
Printer: ${printer}
${arca_key_line}\
${gm_cdu_line}\
" 0 0
}

tui_failure_msg() {
	tui --title 'Something went wrong...' --clear \
		--msgbox 'Something went wrong, DO NOT REBOOT!\nIf possible go over the process again, or contact support.' 0 0
}

tui_success_msg() {
	tui --title 'All good!' --clear \
		--msgbox 'All went well, please reboot now.' 0 0
}

guided_pick_device() {
	device="$(tui_device)"
	handle_tui_return $?
}

guided_pick_platform() {
	platform="$(tui_platform)"
	handle_tui_return $?
}

guided_pick_model() {
	model="$(tui_model)"
	handle_tui_return $?
}

guided_pick_printer() {
	printer="$(tui_printer)"
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
	guided_pick_platform
	guided_pick_model
	guided_pick_printer
	guided_input_arca_key
	guided_input_genmega_cdu_license

	if guided_confirmation; then
		if configure; then
			tui_success_msg
		else
			tui_failure_msg
		fi
	fi
}

guided_install() {
	guided_pick_device
	guided_pick_platform
	guided_pick_model
	guided_pick_printer
	guided_input_arca_key
	guided_input_genmega_cdu_license

	if guided_confirmation; then
		if install; then
			tui_success_msg
		else
			tui_failure_msg
		fi
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
	install|configure|guided)
		shift 1
		"parse_args_${subcmd}" "$@" || "usage_${subcmd}"
		set -x
		"${subcmd}";;
	*) usage;;
esac
