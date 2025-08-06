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
number_of_cassettes='NUMBER_OF_CASSETTES'
number_of_recyclers='NUMBER_OF_RECYCLERS'
image='IMAGE'
xubuntu_image='XUBUNTU_IMAGE'
ubilinux_image='UBILINUX_IMAGE'
image_release_number=''
image_machine_version=''

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
usage: ${progname} configure ${device} ${platform} ${model} [--printer ${printer}]

ROOT may be either the (unmounted) DEVICE, or the mount DIRECTORY of the root partition. If this is an UP or UP4000, DEVICE is likely /dev/mmcblk0.
PLATFORM is the model of the board (for Lamassu machines), or of the maker (for non-Lamassu machines): up4000, upboard, coincloud, generalbytes, genmega.
MODEL is the model of the machine: aveiro, gaia, grandola, tejo, sintra, jcm-ipro-rc, mei-bnr, mei-scr, gemini, gmuk1, gmuk2, wallkiosk, batm3, batm7in.
PRINTER (optional; defaults to none) is the model of the printer: nippon, zebra, genmega, none.
NUMBER_OF_CASSETTES (optional; only for aveiro, tejo) is the number of installed cassettes.
NUMBER_OF_RECYCLERS (optional; only for aveiro, grandola) is the number of installed recyclers.

WARNING: Be sure to specify the correct DEVICE!

EXAMPLES:
To configure an already-installed machine:
	${progname} configure /dev/mmcblk0 upboard tejo --printer nippon

EOF
	exit 1
}

usage_install() {
	cat >&2 <<EOF
usage: ${progname} install ${device} ${image} ${platform} ${model} [--printer ${printer}]

If this is an UP board, DEVICE is likely /dev/mmcblk0.
IMAGE is an image (uncompressed, gzipped, or xzipped) or - to read from stdin.

PLATFORM is the model of the board (for Lamassu machines), or of the maker (for non-Lamassu machines): up4000, upboard, coincloud, generalbytes, genmega.
MODEL is the model of the machine: aveiro, gaia, grandola, tejo, sintra, jcm-ipro-rc, mei-bnr, mei-scr, gemini, gmuk1, gmuk2, wallkiosk, batm3, batm7in.
PRINTER (optional; defaults to none) is the model of the printer: nippon, zebra, genmega, none.
NUMBER_OF_CASSETTES (optional; only for aveiro, tejo) is the number of installed cassettes.
NUMBER_OF_RECYCLERS (optional; only for aveiro, grandola) is the number of installed recyclers.

WARNING: Be sure to specify the correct DEVICE, it will be overwritten!

EXAMPLES:
To install an uncompressed image file:
	${progname} install /dev/mmcblk0 image.img up4000 tejo --printer nippon

To install a gzipped image file:
	${progname} install /dev/mmcblk0 image.img.gz up4000 tejo --printer nippon

EOF
	exit 1
}

usage_guided() {
	cat >&2 <<EOF
usage: ${progname} guided ${xubuntu_image} ${ubilinux_image}

This subcommand presents the user with an interactive menu that they can follow, as an alternative to the other subcommands.

XUBUNTU_IMAGE is a Xubuntu image (uncompressed, gzipped, or xzipped) file.
UBILINUX_IMAGE is an Ubilinux image (uncompressed, gzipped, or xzipped) file.

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

parse_xubuntu_image_file() {
	if [ ! -f "$1" ]; then return 1; fi
	xubuntu_image="$1"
}

parse_ubilinux_image_file() {
	if [ ! -f "$1" ]; then return 1; fi
	ubilinux_image="$1"
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

check_number() {
	echo "$1" | grep -qw '[0-9]\+'
}

parse_number_of_cassettes() {
	check_number "$1" && number_of_cassettes="$1"
}

parse_number_of_recyclers() {
	check_number "$1" && number_of_recyclers="$1"
}

parse_rest() {
	while [ "$#" -ge 2 ]; do
		case "$1" in
			--printer) parse_printer "$2";;
			--number_of_cassettes) parse_number_of_cassettes "$2";;
			--number_of_recyclers) parse_number_of_recyclers "$2";;
		esac || return 1
		shift 2
	done

	if [ "$#" -gt 0 ]; then
		return 1
	fi
}

# ROOT PLATFORM MODEL [REST...]
parse_args_configure() {
	device='ROOT'
	parse_device_or_directory "$1" && shift \
		&& parse_platform "$1" && shift \
		&& parse_model "$1" && shift \
		&& parse_rest "$@"
}

# DEVICE IMAGE PLATFORM MODEL [REST...]
parse_args_install() {
	device='DEVICE'
	parse_device "$1" && shift \
		&& parse_image "$1" && shift \
		&& parse_platform "$1" && shift \
		&& parse_model "$1" && shift \
		&& parse_rest "$@"
}

# IMAGE
parse_args_guided() {
	parse_xubuntu_image_file "$1" \
		&& parse_ubilinux_image_file "$2"
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

try_set_genmega_cdu_license() {
	if [ ! "${platform}" = 'genmega' ]; then
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

try_set_number_of_cassettes() {
	case "${model}" in
		aveiro|tejo);;
		*) return 0;;
	esac

	if ! check_number "${number_of_cassettes}"; then
		return 0
	fi

	local device_config="$1"
	json_setpath_inplace '"billDispenser", "cassettes"' "${number_of_cassettes}" "${device_config}"
}

try_set_number_of_recyclers() {
	case "${model}" in
		aveiro|grandola);;
		*) return 0;;
	esac

	if ! check_number "${number_of_recyclers}"; then
		return 0
	fi

	local device_config="$1"
	json_setpath_inplace '"billDispenser", "recyclers"' "${number_of_recyclers}" "${device_config}"
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
	# copy machine-specific configs
	local lmroot="${rootfs}/opt/lamassu-machine"
	local device_config="${lmroot}/device_config.json"
	cp "${lmroot}/hardware/codebase/${platform}/${model}/device_config.json" "${device_config}"

	# set the correct printer
	json_setpath_inplace '"kioskPrinter", "model"' '"'"${printer}"'"' "${device_config}"

	try_set_number_of_cassettes "${device_config}"
	try_set_number_of_recyclers "${device_config}"

	# set the GenMega CDU license
	try_set_genmega_cdu_license "${device_config}"

	# copy model-specific supervisor configs
	rm -rf "${rootfs}/etc/supervisor/conf.d/"
	cp -r "${lmroot}/hardware/system/${platform}/${model}/supervisor/conf.d/" -t "${rootfs}/etc/supervisor/"
	sed -i "s|^user=.*$|user=$(get_osuser)|;" "${rootfs}/etc/supervisor/conf.d/lamassu-browser.conf"

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

	# install camera-streamer and verify programs
	[ -L "${lmroot}/camera-streamer/camera-streamer" ] || cp -f "${lmroot}/camera-streamer/camera-streamer.amd64" "${lmroot}/camera-streamer/camera-streamer"
	[ -L "${lmroot}/verify/verify" ] || cp -f "${lmroot}/verify/verify.amd64" "${lmroot}/verify/verify"

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

	local should_unmount=''
	if [ -b "${device}" ]; then
		# If device is a block device, mount ${device}*2 into ${rootfs}
		find_partitions
		local rootfs="/mnt/${rootpartition}"
		mkdir -p "${rootfs}"
		mount -t ext4 "${rootpartition}" "${rootfs}"
		should_unmount=yes
	elif [ -d "${device}" ]; then
		# If it's a directory, just use it instead
		rootfs="${device}"
	else
		echo >&2 "Unexpected error: '${device}' is neither a block device nor a directory!"
		exit 1
	fi

	configure_root "${rootfs}"
	if [ "${should_unmount}" = 'yes' ]; then
		umount "${rootfs}"
	fi
}

flash_image() {
	if [ "${image}" = '-' ]; then
		set -x
		dd of="${device}" bs=4M ${ddextra}
	else
		set -x
		case "$(file --brief --mime-type "${image}")" in
			application/gzip) zcat "${image}" | dd of="${device}" bs=4M ${ddextra};;
			application/x-xz) xzcat "${image}" | dd of="${device}" bs=4M ${ddextra};;
			*) dd if="${image}" of="${device}" bs=4M ${ddextra};;
		esac
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

set_image_by_platform_model() {
	case "${platform}" in
		upboard)
			image="${ubilinux_image}"
			image_release_number="${UBILINUX_RELEASE_NUMBER}"
			image_machine_version="${UBILINUX_MACHINE_VERSION}"
			;;
		*)
			image="${xubuntu_image}"
			image_release_number="${LMX_RELEASE_NUMBER}"
			image_machine_version="${LMX_MACHINE_VERSION}"
			;;
	esac
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
	local menumsg='Choose what operation to perform.'
	if [ "${image_release_number}" != '' ]; then menumsg="${menumsg}\nImage release number: ${image_release_number}"; fi
	if [ "${image_machine_version}" != '' ]; then menumsg="${menumsg}\nLamassu machine version: ${image_machine_version}"; fi
	tui --title 'What do you wish to do?' --clear \
		--menu "${menumsg}" 0 0 0 \
		'install' 'Install a Lamassu machine (i.e., flash and configure)' \
		'configure' 'Configure an already-installed Lamassu machine'
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
		up4000) tui_model_ \
			aveiro 'Aveiro' \
			gaia 'Gaia' \
			grandola 'Grândola' \
			tejo 'Tejo' \
			sintra 'Sintra' \
			;;

		upboard) tui_model_ \
			gaia 'Gaia' \
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
		entries='Nippon-2511D-2 Nippon-2511D-2 Zebra-KR-403 Zebra-KR-403'
	fi
	# shellcheck disable=SC2086
	tui --title 'Choose a printer model' --clear \
		--menu 'Select the model of printer your machine features, if any.' 0 0 0 \
		None None \
		${entries}
}

tui_number_of_cassettes() {
	tui --title 'Number of cassettes' \
		--inputbox 'Please input the number of cassettes.' 0 0
}

tui_number_of_recyclers() {
	tui --title 'Number of recyclers' \
		--inputbox 'Please input the number of recyclers.' 0 0
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

	local number_of_cassettes_line=''
	if check_number "${number_of_cassettes}"; then
		number_of_cassettes_line="Number of cassettes: ${number_of_cassettes}\n"
	fi

	local number_of_recyclers_line=''
	if check_number "${number_of_recyclers}"; then
		number_of_recyclers_line="Number of recyclers: ${number_of_recyclers}\n"
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

Platform: ${platform}
Model: ${model}
Printer: ${printer}
${number_of_cassettes_line}\
${number_of_recyclers_line}\

${arca_key_line}\
${gm_cdu_line}\
" 0 0
}

tui_msgbox() {
	local title="$1"
	local text="$2"
	tui --title "${title}" --clear --msgbox "${text}" 0 0
}

tui_failure_msg() {
	tui_msgbox 'Something went wrong...' \
		'Something went wrong, DO NOT REBOOT!\nIf possible go over the process again, or contact support.'
}

tui_success_msg() {
	tui_msgbox 'All good!' \
		'All went well, please reboot now.'
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

guided_pick_number_of_cassettes() {
	case "${model}" in
		aveiro|tejo);;
		*) return 0;;
	esac

	until check_number "${number_of_cassettes}"; do
		number_of_cassettes="$(tui_number_of_cassettes)"
		handle_tui_return $?
	done
}

guided_pick_number_of_recyclers() {
	case "${model}" in
		aveiro|grandola);;
		*) return 0;;
	esac

	until check_number "${number_of_recyclers}"; do
		number_of_recyclers="$(tui_number_of_recyclers)"
		handle_tui_return $?
	done
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
	guided_pick_number_of_cassettes
	guided_pick_number_of_recyclers
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
	guided_pick_number_of_cassettes
	guided_pick_number_of_recyclers
	guided_input_arca_key
	guided_input_genmega_cdu_license

	set_image_by_platform_model
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
