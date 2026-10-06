#!/bin/bash

VRS=v3.12


# Bash Strict Mode (e=errexit, u=nounset, and o pipefail)
set -eo pipefail

# Sets the Internal Field Separator to split strings only on newlines and tabs,
# avoiding word-splitting bugs on variables containing spaces.
IFS=$'\n\t'

# ANSI colors
GRAY="\e[90m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"

BOLD='\033[1m'
UNDERLINE="\e[4m"

# No Color (reset)
NC='\033[0m'

# Call local user & export home directory variable
if [ -n "$SUDO_USER" ]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    echo -e "${RED}⚠️  Error:${NC} This script must be run with sudo\n"
    exit 1
fi

echo -e "\n${YELLOW}╔═════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║                                                             ║${NC}"
echo -e "${YELLOW}║        ${BOLD}<<  Custom Live CD/USB build script ${VRS}  >>        ║${NC}"
echo -e "${YELLOW}║                                                             ║${NC}"
echo -e "${YELLOW}║ Script to build a customizable bootable Live CD/USB desktop ║${NC}"
echo -e "${YELLOW}║ using x64 Debian 13 (Trixie)                                ║${NC}"
echo -e "${YELLOW}║                                                             ║${NC}"
echo -e "${YELLOW}╚═════════════════════════════════════════════════════════════╝${NC}"


######################################
# Set custom working directory here #
######################################

LIVE_DIR="LIVE_BOOT3"
echo -e "${BLUE} 🔧 Build directory:${NC} ${CYAN}${USER_HOME}/${LIVE_DIR}${NC}\n"


############################
# Chroot package variables #
############################

NNN_PKG="https://github.com/jarun/nnn/releases/download/v5.3/nnn-nerd-static-5.3.x86_64.tar.gz"
DINKY_PKG="https://github.com/sedwards2009/dinky/releases/download/v0.11.0/dinky_linux_amd64.tar.gz"
DOXX_PKG="https://github.com/bgreenwell/doxx/releases/download/v0.1.4/doxx-x86_64-unknown-linux-gnu.tar.xz"
NERD_DEJAVU="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/DejaVuSansMono.tar.xz"
NERD_JETBRAINS="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
NERD_ROBOTO="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/RobotoMono.tar.xz"

# Brave browser function
brave_browser_install () {
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
        || { echo "✗ Brave browser keyring failed to download. Check URL."; }
    curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources \
        || { echo "✗ Brave browser failed to add to apt sources. Check URL."; }
    apt update -qq 2>/dev/null
    apt install brave-browser -y -q 2>/dev/null
}

# Make packages and working path available globally
export USER_HOME LIVE_DIR NNN_PKG DINKY_PKG DOXX_PKG NERD_DEJAVU NERD_JETBRAINS NERD_ROBOTO

# Make functions available in chroot
export -f brave_browser_install


##########################
# Declare main functions #
##########################

# Resolve chroot path safely (returns non-zero if DE unset/missing)
chroot_path() {
    local de="${DE:-}"
    [ -z "$de" ] && return 1
    echo "$USER_HOME/$LIVE_DIR/$de/chroot"
}

# Unmount virtual filesystems inside the chroot
unmount_vfs () {
    local root
    root="$(chroot_path)" || return 0
    [ -d "$root" ] || return 0

    # Reverse-mount order: pts -> shm -> mqueue -> dev -> sys/fs/cgroup -> sys -> proc
    local m
    for m in dev/pts dev/shm dev/mqueue dev sys/fs/cgroup sys proc; do
        if grep -qs " $root/$m " /proc/mounts; then
            # Try recursive lazy unmount first, then plain lazy unmount
            umount -R -l "$root/$m" 2>/dev/null || umount -l "$root/$m" 2>/dev/null || true
        fi
    done
    echo
}

# Remove old kernels (keep only the latest kernel version)
remove_old_kernels () {
    # Extract just the current version (e.g. 6.1.0-29) from the latest image package
    keep=$(dpkg -l 'linux-image-*-amd64' \
    | awk '/^ii/{print $2}' \
    | sed 's/^linux-image-//; s/-amd64$//' \
    | sort -V | tail -1)

    # Print kernels to purge
    to_purge=$(dpkg -l 'linux-image-*-amd64' 'linux-headers-*-amd64' \
    | awk '/^ii/{print $2}' \
    | grep -v "linux-image-${keep}-amd64" \
    | grep -v "linux-headers-${keep}-amd64")
    if [[ -z "$to_purge" ]]; then
    	echo "[*] No previous kernels to purge. Continuing..."
    else
    	echo "[!] Will purge kernel/s: $to_purge"
    fi

    # Purge everything except the latest version
    dpkg -l 'linux-image-*-amd64' 'linux-headers-*-amd64' \
    | awk '/^ii/{print $2}' \
    | grep -v "linux-image-${keep}-amd64" \
    | grep -v "linux-headers-${keep}-amd64" \
    | xargs -r apt-get purge -y

    # Cleanup repositories
    apt-get autoremove --purge -y 2>/dev/null
    apt autoclean -y 2>/dev/null
}

# Select target desktop environment
env_select () {
    echo -e "\n═════════════════════════════════════════════════════════"
    echo -e "${YELLOW}Choose target desktop environment for Live CD/USB build${NC}"
    echo -e "═════════════════════════════════════════════════════════\n"
    echo -e "  ${BLUE}1)${NC} ${CYAN}CLI${NC}   - Command Line Interface only (no GUI)"
    echo -e "  ${BLUE}2)${NC} ${CYAN}KDE${NC}   - KDE Plasma Desktop"
    echo -e "  ${BLUE}3)${NC} ${CYAN}GNOME${NC} - GNOME Desktop"
    echo -e "  ${BLUE}4)${NC} ${CYAN}MATE${NC}  - MATE Desktop (Classic GNOME)"
    echo -e "  ${BLUE}5)${NC} ${CYAN}XFCE${NC}  - XFCE Lightweight Desktop"
    echo -e "  ${BLUE}6)${NC} ${BLUE}Exit${NC}  - Cancel and Exit Script\n"

    while true; do
        read -rp "Enter choice [1-6]: " DE_NUM
        case "$DE_NUM" in
            "1") DE="CLI"
                break ;;
            "2") DE="KDE"
                break ;;
            "3") DE="GNOME"
                break ;;
            "4") DE="MATE"
                break ;;
            "5") DE="XFCE"
                break ;;
            "6") echo -e "${BLUE}Desktop installtion cancelled.${NC}\n"
                exit 0 ;;
             *) echo -e "${RED}✗ Invalid selection.${NC} Please choose a number from the list [1-6].\n"
                ;;
        esac
    done
    echo -e "\n${CYAN}'${DE}'${NC} environment selected.\n"
}

# Choices after previous DE build is found
env_update () {
    echo -e "\n═════════════════════════════════════════════════════════"
    echo -e "${YELLOW}Existing live CD build folder found.${NC} Please select${NC}"
    echo -e "═════════════════════════════════════════════════════════\n"
    echo -e "  ${BLUE}1)${NC} ${CYAN}Rebuild Live CD/USB iso${NC} - Reauthor iso"
    echo -e "  ${BLUE}2)${NC} ${CYAN}Delete target build folder${NC} - Remove workspace"
    echo -e "  ${BLUE}3)${NC} ${CYAN}Chroot into target build${NC} - Make custom changes"
    echo -e "  ${BLUE}4)${NC} ${BLUE}Exit${NC} - Cancel and Exit Script\n"

    while [[ -d "$USER_HOME/$LIVE_DIR/$DE" ]]; do
        read -rp "Enter choice [1-4]: " CHOICE_NUM1
        case "$CHOICE_NUM1" in
            "1") echo -e "\n${CYAN}'${DE}'${NC} Live CD/USB iso will be recreated from existing build....\n"
                 echo -e "${BLUE}Rebuilding iso...${NC}"
                 unmount_vfs # Unmount virtual filesystems
                 rm -rf "$USER_HOME/$LIVE_DIR/$DE/chroot/tmp/*" 2>/dev/null # Clear tmp dir
                 build_iso # Rebuild iso
                 ;;
            "2") echo -e "\n${RED}⚠️  Warning:${NC} ${DE} build folders & files will be permanently deleted."
                 read -rp "Are you sure? [y/n] " DEL_RESPONSE1
                 if [[ "${DEL_RESPONSE1,,}" == "n" ]]; then
                     echo -e "${BLUE}Deletion cancelled.${NC}\n"
                 elif [[ "${DEL_RESPONSE1,,}" == "y" ]]; then
                     unmount_vfs
                     echo -e "${BLUE}${DE} folder deleting...${NC}"

                     # Aborts if any dir variable is unset or empty
                     rm -rf "${USER_HOME:?USER_HOME is empty}/${LIVE_DIR:?LIVE_DIR is empty}/${DE:?DE is empty}" || { echo -e "${RED}✗ Build folder deletion failed (unset?)${NC}" >&2; exit 1; }
                     echo -e "${GREEN}✓ ${DE} build folder deleted.${NC}\n"
                     exit 0
                 else
                     echo -e "${RED}✗ Invalid selection.${NC} Please choose a number from the list [1-4]."
                 fi
                 ;;
            "3") chroot_access # Interactive chroot session
                 ;;
            "4") echo -e "${BLUE}Script will exit."
                 exit 0
                 ;;
            *)   echo -e "${RED}✗ Invalid selection.${NC} Please choose a number from the list [1-4]."
                 ;;
        esac
    done
}


# Create username & password before build
preseed_user_pass () {
    echo -e "═════════════════════════════════════════════════════════\n"
    while true; do
	echo -e "${YELLOW}Create account username${NC}"
	read -rp "(sudo enabled & root account disabled): " USER1
        if [[ -n "$USER1" && "$USER1" =~ ^[a-z][a-z0-9_-]*$ && ${#USER1} -le 32 ]]; then
	        echo -e "\n${CYAN}'$USER1'${NC} created"
	    break
        else
            echo -e "${RED}✗ Invalid username.${NC} Must start with a letter, contain only lowercase letters, numbers, hyphens, underscores, and be 32 chars or less.\n"
        fi
    done

    echo

    # Initialize attempt counter
    attempts=0
    max_attempts=3

    # Loop for password input and confirmation
    while [[ "$attempts" -lt "$max_attempts" ]]; do
        read -rsp "Enter password for '$USER1': " PASS1
        echo
        read -rsp "Confirm password: " PASS2
        echo
        if [[ "$PASS1" == "$PASS2" ]]; then
            echo -e "${GREEN}✓ Password confirmed.\n${NC}"
            break
        else
            ((attempts++))
            if [[ "$attempts" -lt "$max_attempts" ]]; then
                echo -e "${RED}✗ Password does not match.${NC} You have $((max_attempts - attempts)) attempt[s] left.\n"
            else
                echo -e "${RED}✗ Password does not match. Maximum attempts reached. Script will exit.${NC}\n"
                exit 1
            fi
        fi
    done
}

# Interactive chroot access
chroot_access () {
    local root
    root="$(chroot_path)" || { echo -e "${RED}✗ Chroot path not found.${NC}"; return 1; }

    # Mount necessary virtual filesystems (parent /dev BEFORE /dev/pts)
    if ! grep -qs " $root/dev " /proc/mounts; then
        mount --bind /dev "$root/dev" 2>/dev/null || true
    fi
    if ! grep -qs " $root/dev/pts " /proc/mounts; then
        mount --bind /dev/pts "$root/dev/pts" 2>/dev/null || true
    fi
    if [[ -d /dev/shm ]] && ! grep -qs " $root/dev/shm " /proc/mounts; then
        mount --bind /dev/shm "$root/dev/shm" 2>/dev/null || true
    fi
    if ! grep -qs " $root/proc " /proc/mounts; then
        mount --bind /proc "$root/proc" 2>/dev/null || true
    fi
    if ! grep -qs " $root/sys " /proc/mounts; then
        mount --bind /sys "$root/sys" 2>/dev/null || true
    fi

    # Copy resolv.conf for network access in chroot
    cp /etc/resolv.conf "$root/etc/"

    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${BLUE}Entering chroot environment${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "${CYAN}You are now inside the ${DE} chroot.${NC}"
    echo -e "${CYAN}Make any desired changes to the system.${NC}"
    echo -e "${CYAN}Type 'exit' or <Ctrl+D> when finished to continue build.${NC}"
    echo -e "${BLUE}=========================================================${NC}\n"

    # Find target username & export variables for the chroot session
    CHRUSER1=$(find "$root/home" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -n1)
    export DE CHRUSER1

    # Export for chroot
    export -f remove_old_kernels

    # Enter chroot interactively
    chroot "$root" /bin/bash
    local CHROOT_EXIT=$?

    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${GREEN}Exited chroot environment${NC}"
    echo -e "${BLUE}=========================================================${NC}\n"

    # Check if user wants to abort or continue iso build
    if [ "$CHROOT_EXIT" -eq "0" ]; then
        echo -e "\n═════════════════════════════════════════════════════════"
        echo -e "${YELLOW}Choose from the following options${NC}"
        echo -e "═════════════════════════════════════════════════════════\n"
        echo -e "  ${BLUE}1)${NC} ${CYAN}Rebuild Live CD/USB iso${NC} - Reauthor iso"
        echo -e "  ${BLUE}2)${NC} ${BLUE}Exit${NC} - Cancel and Exit Script"
        echo -e "\n${GRAY}<< Press any other key to return to previous menu >>${NC}\n"

        read -rp "Enter choice [1-2]: " CHOICE_NUM2
        case "$CHOICE_NUM2" in
            "1") echo -e "${GREEN}Cleaning up and preparing workspace...${NC}"
            	 # Cleanup before building iso
                 chroot "$root" /bin/bash << CHR_EOL
remove_old_kernels
rm -rf /tmp/* 2>/dev/null
echo > /root/.bash_history
[[ -f "/home/${CHRUSER1}/.bash_history" ]] && echo > "/home/${CHRUSER1}/.bash_history"
CHR_EOL
                 unmount_vfs
                 build_iso
                 ;;
            "2") unmount_vfs
                 echo -e "${BLUE}Script will exit.${NC}\n"
                 exit 0
                 ;;
            *)   echo -e "Returning to previous menu...\n"
                 env_update
                 ;;
        esac
    else
        echo -e "${RED}✗ Chroot session ended with errors or user abort.${NC}\n"
        exit 1
    fi
}

# Build livecd/usb image
build_iso () {
    # Live environment directories
    mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT"
    mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/x86_64-efi"
    mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/fonts"
    mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/isolinux"
    mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/live"
    mkdir -p "$USER_HOME/$LIVE_DIR/$DE/tmp"

    # Check and remove previous squash & iso, if found
    shopt -s nullglob
    iso_files=( "$USER_HOME/$LIVE_DIR/$DE"/*.iso )
    sha_files=( "$USER_HOME/$LIVE_DIR/$DE"/*.sha256sum )
    if [[ ${#iso_files[@]} -gt 0 || ${#sha_files[@]} -gt 0 ]]; then
        rm -f "${iso_files[@]}" "${sha_files[@]}" "$USER_HOME/$LIVE_DIR/$DE/staging/live/filesystem.squashfs" 2>/dev/null
        echo -e "${BLUE}Previous squash, iso, and/or checksum files deleted.${NC}\n"
    fi

    # Compress filesystem
    echo -e "${BLUE}Compressing filesystem...${NC}"
    mksquashfs "$USER_HOME/$LIVE_DIR/$DE/chroot" "$USER_HOME/$LIVE_DIR/$DE/staging/live/filesystem.squashfs" -e boot -comp xz -Xbcj x86 -b 1M

    # Copy only ONE kernel & initrd into staging when multiple files exist
    latest_kern=$(ls "$USER_HOME/$LIVE_DIR/$DE/chroot/boot/vmlinuz-"* | sort -V | tail -1)
    latest_initrd=$(ls "$USER_HOME/$LIVE_DIR/$DE/chroot/boot/initrd.img-"* | sort -V | tail -1)
    cp "$latest_kern"   "$USER_HOME/$LIVE_DIR/$DE/staging/live/vmlinuz"
    cp "$latest_initrd" "$USER_HOME/$LIVE_DIR/$DE/staging/live/initrd"

    ###########################################
    # ISOLINUX Configuration (BIOS/Legacy)    #
    ###########################################

    cat > "$USER_HOME/$LIVE_DIR/$DE/staging/isolinux/isolinux.cfg" << 'ISOLINUX_EOF'
# Enable graphical menu
UI vesamenu.c32

# Menu appearance
MENU TITLE Debian 13 Live CD/USB Boot Menu
MENU BACKGROUND splash.png
MENU RESOLUTION 800 600

# Modern Blue Theme (for dark backgrounds)
MENU COLOR title        1;36;44    #ff8c00ff #00000000 std
MENU COLOR border       30;44      #00000000 #00000000 none
MENU COLOR screen       37;40      #e0e1ddff #00000000 std
MENU COLOR sel          7;37;40    #ffffffff #0077b6ff all
MENU COLOR unsel        37;44      #adb5bdff #00000000 std
MENU COLOR disabled     30;44      #6c757dff #00000000 std
MENU COLOR help         1;33;40    #ffd166ff #00000000 std
MENU COLOR msg07        37;40      #ced4daff #00000000 std
MENU COLOR scrollbar    30;44      #495057ff #00000000 std
MENU COLOR tabmsg       31;40      #48cae4ff #00000000 std
MENU COLOR timeout      1;37;40    #ef476fff #00000000 std
MENU COLOR timeout_msg  1;33;40    #ffd166ff #00000000 std
MENU COLOR cmdmark      1;36;40    #00b4d8ff #00000000 std
MENU COLOR cmdline      37;40      #f8f9faff #00000000 std

# Menu layout
MENU MARGIN 10
MENU ROWS 12
MENU TABMSGROW 20
MENU CMDLINEROW 22
MENU TIMEOUTROW 24
MENU HELPMSGROW 26
MENU VSHIFT 4
MENU WIDTH 70

# Default boot entry
DEFAULT linux-toram
TIMEOUT 100
MENU AUTOBOOT Starting in # second{,s}...

MENU SEPARATOR

LABEL linux-toram
  MENU LABEL ^1. Debian 13 Live - Load to RAM [Remove USB]
  MENU DEFAULT
  TEXT HELP
  Loads entire system into RAM for best performance.
  You can remove USB drive after boot completes.
  Recommended for 8GB or greater RAM systems.
  ENDTEXT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live toram toram=filesystem.squashfs quiet splash plymouth.enable=1

LABEL linux-live
  MENU LABEL ^2. Debian 13 Live - Normal [Keep USB]
  TEXT HELP
  Read-only filesystem and changes loaded to RAM.
  USB drive must remain connected.
  Recommended for less than 8GB RAM systems.
  ENDTEXT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live quiet splash plymouth.enable=1

LABEL linux-safe
  MENU LABEL ^3. Debian 13 Live - Safe Graphics Mode
  TEXT HELP
  Falls back to basic graphics drivers.
  Use if experiencing display issues.
  ENDTEXT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live toram nomodeset noacpi

MENU SEPARATOR

LABEL hardware
  MENU LABEL ^5. Hardware Detection Tool
  TEXT HELP
  Boot hardware detection and reporting.
  ENDTEXT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live toram hw-detect

MENU SEPARATOR

LABEL reboot
  MENU LABEL ^R. Reboot System
  TEXT HELP
  Restart the computer.
  ENDTEXT
  COM32 reboot.c32

LABEL shutdown
  MENU LABEL ^S. Shutdown System
  TEXT HELP
  Power off the computer.
  ENDTEXT
  COM32 poweroff.c32
ISOLINUX_EOF


    ###########################################
    # GRUB Configuration (EFI)                #
    ###########################################

    cat > "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/grub.cfg" << 'GRUB_EOF'
# Load GRUB modules
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod all_video
insmod font
insmod gfxterm
insmod gfxmenu
insmod png
insmod jpeg
insmod gettext
insmod gzio
insmod search_label

# Locate the live ISO and rebase $root/$prefix
search --no-floppy --set=root --label DEB13-LIVE
set prefix=($root)/boot/grub

# Fallback: if the search failed, stay on the EFI partition where
# mirrored copies of the font/theme live.
if ! [[ -f ($root)/boot/grub/fonts/unicode.pf2 ]]; then
    set prefix=($root)/EFI/BOOT
fi
export prefix

# Plain black background
set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm

# Load fonts
loadfont unicode
set locale_dir=$prefix/locale
set lang=en_US

# Boot menu behavior
set timeout=10
set default=0

menuentry "Debian 13 Live - Load to RAM [Remove USB]" --class debian {
    search --no-floppy --set=root --label DEB13-LIVE
    linux ($root)/live/vmlinuz boot=live toram toram=filesystem.squashfs quiet splash plymouth.enable=1
    initrd ($root)/live/initrd
}

menuentry "Debian 13 Live - Normal Boot [Keep USB]" --class debian {
    search --no-floppy --set=root --label DEB13-LIVE
    linux ($root)/live/vmlinuz boot=live quiet splash plymouth.enable=1
    initrd ($root)/live/initrd
}

menuentry "Debian 13 Live - Safe Graphics Mode" --class debian {
    search --no-floppy --set=root --label DEB13-LIVE
    linux ($root)/live/vmlinuz boot=live toram nomodeset
    initrd ($root)/live/initrd
}

submenu "Advanced Options" {
    menuentry "Debug Mode [Verbose TORAM Boot]" {
        search --no-floppy --set=root --label DEB13-LIVE
        linux ($root)/live/vmlinuz boot=live toram debug systemd.log_level=debug
        initrd ($root)/live/initrd
    }

    menuentry "Recovery Console [Live Boot]" {
        search --no-floppy --set=root --label DEB13-LIVE
        linux ($root)/live/vmlinuz boot=live single
        initrd ($root)/live/initrd
    }

    menuentry "Hardware Detection" {
        search --no-floppy --set=root --label DEB13-LIVE
        linux ($root)/live/vmlinuz boot=live toram hw-detect
        initrd ($root)/live/initrd| sort -V | tail -1*
    }
}

menuentry "Reboot System" { reboot }
menuentry "Shutdown System" { halt }
GRUB_EOF


    ###########################################
    # Generate ISOLINUX Background            #
    ###########################################

    echo -e "${BLUE}Generating ISOLINUX background...${NC}"

    if ! command -v convert &> /dev/null; then
        echo -e "${YELLOW}Installing ImageMagick...${NC}"
        apt install imagemagick -y -q 2>/dev/null || echo -e "${RED}Failed to install ImageMagick. Skipping ISOLINUX background.${NC}"
    fi

    if command -v convert &> /dev/null; then
        # Solid black background for the ISOLINUX vesamenu
        convert -size 640x480 xc:black \
            "$USER_HOME/$LIVE_DIR/$DE/staging/isolinux/splash.png" 2>/dev/null

        if [[ -f "$USER_HOME/$LIVE_DIR/$DE/staging/isolinux/splash.png" ]]; then
            echo -e "${GREEN}✓ ISOLINUX background created${NC}"
        else
            echo -e "${RED}✗ ISOLINUX background failed${NC}"
        fi
    else
        echo -e "${YELLOW}ImageMagick not available, skipping ISOLINUX background generation${NC}"
    fi

    ###########################################
    # Copy Bootloader Files + GRUB Font       #
    ###########################################

    cp /usr/lib/ISOLINUX/isolinux.bin "$USER_HOME/$LIVE_DIR/$DE/staging/isolinux/"
    cp /usr/lib/syslinux/modules/bios/* "$USER_HOME/$LIVE_DIR/$DE/staging/isolinux/"

    if [[ ! -f "$USER_HOME/$LIVE_DIR/$DE/staging/isolinux/vesamenu.c32" ]]; then
        echo -e "${YELLOW}Error: 'vesamenu.c32' not found! Searching...${NC}"
        local found
        if found=$(find /usr -name "vesamenu.c32" -print -quit 2>/dev/null) && [[ -n "$found" ]]; then
            cp "$found" "$USER_HOME/$LIVE_DIR/$DE/staging/isolinux/"
        else
            echo -e "${RED}⚠️  Cannot find 'vesamenu.c32'${NC}"
        fi
    fi

    [[ ! -d "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/x86_64-efi/" ]] && mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/x86_64-efi/"
    cp -r /usr/lib/grub/x86_64-efi/* "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/x86_64-efi/"
    [[ ! -d "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/x86_64-efi/" ]] && mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/x86_64-efi/"
    cp -r /usr/lib/grub/x86_64-efi/* "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/x86_64-efi/"

    # Copy the unicode font so `loadfont unicode` resolves under $prefix/fonts
    if [[ -f /usr/share/grub/unicode.pf2 ]]; then
        cp /usr/share/grub/unicode.pf2 "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/fonts/"
    else
        echo -e "${YELLOW}[!] /usr/share/grub/unicode.pf2 not found — install grub-common${NC}"
    fi

    # Mirror font + theme into EFI tree as a fallback
    mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/fonts"
    mkdir -p "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/themes"
    [[ -f /usr/share/grub/unicode.pf2 ]] && cp /usr/share/grub/unicode.pf2 "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/fonts/"

    # Memtest
    if [[ -f /boot/memtest86+.bin ]]; then
        cp /boot/memtest86+.bin "$USER_HOME/$LIVE_DIR/$DE/staging/live/" 2>/dev/null
    else
        touch "$USER_HOME/$LIVE_DIR/$DE/staging/live/memtest86+.bin"
    fi

    ###########################################
    # Create EFI Boot Images                  #
    ###########################################

    cp "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/grub.cfg" "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/"

    cat > "$USER_HOME/$LIVE_DIR/$DE/tmp/grub-embed.cfg" <<'EOF'
if ! [[ -d "$cmdpath" ]]; then
    if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "$cmdpath"; then
        cmdpath="${isodevice}/EFI/BOOT"
    fi
fi
configfile "${cmdpath}/grub.cfg"
EOF

    grub-mkstandalone -O i386-efi \
        --modules="part_gpt part_msdos fat iso9660 all_video png jpeg gfxterm gfxmenu font search_label" \
        --locales="" --themes="" --fonts="" \
        --output="$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/BOOTIA32.EFI" \
        "boot/grub/grub.cfg=$USER_HOME/$LIVE_DIR/$DE/tmp/grub-embed.cfg"

    grub-mkstandalone -O x86_64-efi \
        --modules="part_gpt part_msdos fat iso9660 all_video png jpeg gfxterm gfxmenu font search_label" \
        --locales="" --themes="" --fonts="" \
        --output="$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/BOOTx64.EFI" \
        "boot/grub/grub.cfg=$USER_HOME/$LIVE_DIR/$DE/tmp/grub-embed.cfg"

    # Create UEFI boot disk image
    cd "$USER_HOME/$LIVE_DIR/$DE/staging" && \
    dd if=/dev/zero of=efiboot.img bs=1M count=20 && \
    mkfs.vfat efiboot.img && \
    mmd -i efiboot.img ::/EFI ::/EFI/BOOT && \
    mcopy -vi efiboot.img \
        "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/BOOTIA32.EFI" \
        "$USER_HOME/$LIVE_DIR/$DE/staging/EFI/BOOT/BOOTx64.EFI" \
        ::/EFI/BOOT/ && \
    mcopy -vi efiboot.img \
        "$USER_HOME/$LIVE_DIR/$DE/staging/boot/grub/grub.cfg" \
        ::/EFI/BOOT/

    ###########################################
    # Generate Final ISO                      #
    ###########################################

    # Copy kernel files to boot directory (silent fail if not found)
    cp -L "$USER_HOME/$LIVE_DIR/$DE/chroot/boot/vmlinuz-"* "$USER_HOME/$LIVE_DIR/$DE/staging/boot/vmlinuz" 2>/dev/null || \
    cp "$USER_HOME/$LIVE_DIR/$DE/chroot/boot/vmlinuz-"* "$USER_HOME/$LIVE_DIR/$DE/staging/boot/"

    cp -L "$USER_HOME/$LIVE_DIR/$DE/chroot/boot/initrd.img-"* "$USER_HOME/$LIVE_DIR/$DE/staging/boot/initrd" 2>/dev/null || \
    cp "$USER_HOME/$LIVE_DIR/$DE/chroot/boot/initrd.img-"* "$USER_HOME/$LIVE_DIR/$DE/staging/boot/"

    echo -e "${BLUE}Generating ISO image...${NC}"

    # Build the ISO
    xorriso -as mkisofs \
        -iso-level 3 \
        -o "$USER_HOME/$LIVE_DIR/$DE/debian13-$DE-x64-livecd.iso" \
        -full-iso9660-filenames \
        -volid "DEB13-LIVE" \
        --mbr-force-bootable \
        -partition_offset 16 \
        -joliet \
        -joliet-long \
        -rational-rock \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -eltorito-boot isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/isolinux.cat \
        -eltorito-alt-boot \
        -e --interval:appended_partition_2:all:: \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B \
        "$USER_HOME/$LIVE_DIR/$DE/staging/efiboot.img" \
        "$USER_HOME/$LIVE_DIR/$DE/staging" \
        || { echo -e "${RED}✗ ISO build failed${NC}"; exit 1; }

    # Set permissions
    chmod 644 "$USER_HOME/$LIVE_DIR/$DE/debian13-$DE-x64-livecd.iso"

    if [[ -f "$USER_HOME/$LIVE_DIR/$DE/debian13-$DE-x64-livecd.iso" ]]; then
        echo -e "${GREEN}✓ ${DE} Live CD/USB build completed${NC}"
        echo -e "${CYAN}💿 ISO: $USER_HOME/$LIVE_DIR/$DE/debian13-$DE-x64-livecd.iso${NC}\n"
        exit 0
    else
        echo -e "${RED}✗ Build failed — no ISO produced. Please review log.${NC}"
        exit 1
    fi
}


# Execute desktop environment selection
env_select

# Execute build update selection when previous build is found
[[ -d "$USER_HOME/$LIVE_DIR/$DE" ]] && env_update

# Execute pre-seed username & password loop
preseed_user_pass

###########################
# Build iso (initial run) #
###########################

echo -e "${BLUE}Starting Live CD/USB build...${NC}"

# Install prerequisite packages
apt update -qq
apt install debootstrap squashfs-tools xorriso isolinux syslinux-efi grub-efi-amd64-bin grub-efi-ia32-bin mtools dosfstools whois -y -q

# Create workspace for building live environment
mkdir -p "$USER_HOME/$LIVE_DIR/$DE"

# Bootstrap Debian 13 (trixie)
debootstrap --arch=amd64 --variant=minbase trixie "$USER_HOME/$LIVE_DIR/$DE/chroot" http://ftp.us.debian.org/debian/

# Export variables for chroot
export DE USER1 PASS1

# Chroot into live build environment
chroot "$USER_HOME/$LIVE_DIR/$DE/chroot" /bin/bash << SCRIPT_EOT
    # Update sources.list
    cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF

    # Mount system directories (if not already mounted) - parent /dev BEFORE /dev/pts
    if ! mountpoint -q /proc; then
        mount -t proc proc /proc
    fi
    if ! mountpoint -q /sys; then
        mount -t sysfs sys /sys
    fi
    if ! mountpoint -q /dev; then
        mount --rbind /dev /dev
    fi
    # /dev/pts comes along automatically with --rbind;
    # only mount it separately if you used a fresh devtmpfs:
    if ! mountpoint -q /dev/pts; then
        mount -t devpts devpts /dev/pts
    fi

    # Exit script gracefully if errors encountered (in-chroot cleanup)
    trap 'umount /dev/pts 2>/dev/null; umount /dev 2>/dev/null; umount /sys 2>/dev/null; umount /proc 2>/dev/null; unset USER1 PASS1; exit' ERR EXIT

    apt update -qq

    # Essential programs
    apt install linux-image-amd64 live-boot systemd-sysv whois -y -q

    # Plymouth boot splash function
install_plymouth() {
    # Install plymouth
    DEBIAN_FRONTEND=noninteractive apt install plymouth plymouth-themes grub2-common hwinfo -y -q 2>/dev/null

    # Standard themes (uncomment to your preference)
    plymouth-set-default-theme spinner -R
    #plymouth-set-default-theme solar -R
    #plymouth-set-default-theme tribar -R
    #plymouth-set-default-theme glow -R
    #plymouth-set-default-theme spinfinity -R

    # Ensure plymouth is in initramfs
    echo "FRAMEBUFFER=y" > /etc/initramfs-tools/conf.d/plymouth || true

    # Update initramfs to include Plymouth
    update-initramfs -u -k all 2>/dev/null
}


    # Desktop environments:

    #################################
    # CLI (no gui, no xorg, no x11) #
    #################################
setup_cli() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install network-manager sudo nano gnupg zip unzip rar locales firmware-amd-graphics firmware-atheros amd64-microcode firmware-iwlwifi firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode wget exfat-fuse ntfs-3g lvm2 dosfstools mtools duf curl eza htop lm-sensors toilet figlet ssh sshfs parted screen rsync git cryptsetup command-not-found xz-utils file manpages man-db ufw lsof -y -q

    # Add your custom packages here
    #apt install fail2ban aria2 ... -y

    # Command line docx viewer
    cd /tmp
    curl -L "$DOXX_PKG" | tar xJ || { echo "✗ Doxx installed failed. Check URL."; }
    chmod +x doxx && mv doxx /usr/local/bin/ 2>/dev/null

    # Command line text editor
    curl -L "$DINKY_PKG" | tar xz || { echo "✗ Dinky installed failed. Check URL."; }
    chmod +x dinky && mv dinky /usr/local/bin/ 2>/dev/null

    # Command line file manager
    curl -L "$NNN_PKG" | tar xz || { echo "✗ NNN installed failed. Check URL."; }
    chmod +x nnn-nerd-static && mv nnn-nerd-static /usr/local/bin/nnn 2>/dev/null

    # Initialize hostname
    echo "deb13-${DE}-live" > /etc/hostname
    sed -i "1s/^/127.0.0.1\tdeb13-${DE}-live\n/" /etc/hosts

    # Autologin user
    mkdir -p /etc/systemd/system/getty@.service.d/
    cat << EOF > /etc/systemd/system/getty@.service.d/override.conf
[Service]
ExecStart=
ExecStart=/sbin/agetty --autologin ${USER1} --noclear %I \$TERM
EOF

    systemctl set-default multi-user.target
    systemctl daemon-reload
}

    ######################
    # KDE Plasma desktop #
    ######################
setup_kde() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install kde-plasma-desktop plasma-nm sddm sddm-theme-breeze kwin-addons dolphin konsole sudo nano git pipx gnupg dmsetup zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g dosfstools mtools pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs ssh sshfs screen rsync git cryptsetup command-not-found xz-utils file manpages man-db ufw lsof -y -q

    # Add your custom packages here
    #apt install fail2ban aria2 ... -y

    # Command line file manager
    cd /tmp
    curl -L "$NNN_PKG" | tar xz || { echo "✗ NNN installed failed. Check URL."; }
    chmod +x nnn-nerd-static && mv nnn-nerd-static /usr/local/bin/nnn 2>/dev/null

    # Media, codecs, & graphics packages
    #apt install vlc intel-media-va-driver ffmpeg gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav -y

    # Office packages
    #apt install libreoffice-writer libreoffice-calc -y

    # Remove unwanted packages
    apt remove kdeconnect konqueror plasma-welcome khelpcenter* firefox* libreoffice-math -y

    # Brave web browser (resource useage heavy)
    brave_browser_install

    # Librewolf web browser (resource useage medium)
    #apt install extrepo -y
    #extrepo enable librewolf && extrepo update librewolf
    #apt update && apt install librewolf -y

    # Falkon web browser (resource useage light)
    #apt install falkon -y

    # Printer packages
    #apt install cups system-config-printer foomatic-db openprinting-ppds tcl-tclreadline psutils -y
    #systemctl enable cups

    # Initialize hostname
    echo "deb13-${DE}-live" > /etc/hostname
    sed -i "1s/^/127.0.0.1\tdeb13-${DE}-live\n/" /etc/hosts

    # Autologin user
    mkdir -p /etc/sddm.conf.d
    cat << EOF > /etc/sddm.conf.d/autologin.conf
[Autologin]
User=${USER1}
Session=plasma.desktop
Relogin=false
EOF

}

    #################
    # GNOME desktop #
    #################
setup_gnome() {
    # Essential gnome packages (minimal)
    DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends gnome-core gdm3 network-manager-gnome gedit -y -q

    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install sudo nano git pipx gnupg dmsetup zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g dosfstools mtools pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs ssh sshfs screen rsync git command-not-found xz-utils file manpages man-db ufw lsof -y -q

    # Add your custom packages here
    #apt install fail2ban aria2 ... -y

    # Command line file manager
    cd /tmp
    curl -L "$NNN_PKG" | tar xz || { echo "✗ NNN installed failed. Check URL."; }
    chmod +x nnn-nerd-static && mv nnn-nerd-static /usr/local/bin/nnn 2>/dev/null

    # Media, codecs, & graphics packages
    #apt install vlc intel-media-va-driver ffmpeg gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav -y

    # Office packages
    #apt install libreoffice-writer libreoffice-calc -y

    # Remove unwanted packages
    apt remove firefox* libreoffice-math -y

    # Brave browser (resource useage heavy)
    brave_browser_install

    # Librewolf web browser (resource useage medium)
    #apt install extrepo -y
    #extrepo enable librewolf && extrepo update librewolf
    #apt update && apt install librewolf -y

    # Falkon web browser (resource useage light)
    #apt install falkon -y

    # Printer packages
    #apt install cups system-config-printer foomatic-db openprinting-ppds tcl-tclreadline psutils -y -q
    #systemctl enable cups

    # Initialize hostname
    echo "deb13-${DE}-live" > /etc/hostname
    sed -i "1s/^/127.0.0.1\tdeb13-${DE}-live\n/" /etc/hosts

    # Autologin user
    cat << EOF > /etc/gdm3/custom.conf
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${USER1}
EOF

}

    ################
    # MATE desktop #
    ################
setup_mate() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install mate-desktop-environment-core lightdm mate-media pulseaudio pulseaudio-utils alsa-utils network-manager-gnome mate-power-manager upower acpid sudo nano git pipx gnupg dmsetup unrar rar zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs keepassxc xclip mousepad ssh sshfs screen rsync git command-not-found xz-utils file manpages man-db ufw lsof -y -q

    # Add your custom packages here
    #apt install fail2ban aria2 ... -y

    # Command line file manager
    cd /tmp
    curl -L "$NNN_PKG" | tar xz || { echo "✗ NNN installed failed. Check URL."; }
    chmod +x nnn-nerd-static && mv nnn-nerd-static /usr/local/bin/nnn 2>/dev/null

    # Media, codecs, & graphics packages
    #apt install vlc intel-media-va-driver ffmpeg gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav -y

    # Office packages
    #apt install libreoffice-writer libreoffice-calc -y

    # Remove unwanted packages
    apt remove firefox* libreoffice-math -y

    # Brave browser (resource useage heavy)
    #brave_browser_install

    # Librewolf web browser (resource useage medium)
    apt install extrepo -y -q
    extrepo enable librewolf && extrepo update librewolf
    apt update && apt install librewolf -y -q

    # Falkon web browser (resource useage light)
    #apt install falkon -y

    # Printer packages
    #apt install cups system-config-printer foomatic-db openprinting-ppds tcl-tclreadline psutils -y -q
    #systemctl enable cups

    # Initialize hostname
    echo "deb13-${DE}-live" > /etc/hostname
    sed -i "1s/^/127.0.0.1\tdeb13-${DE}-live\n/" /etc/hosts

    # Autologin user
    mkdir -p /usr/share/lightdm/lightdm.conf.d
    cat << EOF > /usr/share/lightdm/lightdm.conf.d/60-lightdm-gtk-greeter.conf
[Seat:*]
greeter-session=lightdm-gtk-greeter
autologin-user=${USER1}
EOF

}

    ################
    # XFCE desktop #
    ################
setup_xfce() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install xfce4 xfce4-goodies lightdm network-manager-gnome sudo nano git pipx gnupg ssh dmsetup unrar rar zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs keepassxc xclip ssh sshfs screen rsync git command-not-found xz-utils file manpages man-db ufw lsof -y -q

    # Add your custom packages here
    #apt install fail2ban aria2 ... -y

    # Command line file manager
    cd /tmp
    curl -L "$NNN_PKG" | tar xz || { echo "✗ NNN installed failed. Check URL."; }
    chmod +x nnn-nerd-static && mv nnn-nerd-static /usr/local/bin/nnn 2>/dev/null

    # Media, codecs, & graphics packages
    #apt install vlc intel-media-va-driver ffmpeg gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav -y

    # Office packages
    #apt install libreoffice-writer libreoffice-calc -y

    # Remove unwanted packages
    apt remove firefox* libreoffice-math -y

    # Brave browser (resource useage heavy)
    #brave_browser_install

    # Librewolf web browser (resource useage medium)
    #apt install extrepo -y
    #extrepo enable librewolf && extrepo update librewolf
    #apt update && apt install librewolf -y

    # Falkon web browser (resource useage light)
    apt install falkon -y -q

    # Printer packages
    #apt install cups system-config-printer foomatic-db openprinting-ppds tcl-tclreadline psutils -y -q
    #systemctl enable cups

    # Initialize hostname
    echo "deb13-${DE}-live" > /etc/hostname
    sed -i "1s/^/127.0.0.1\tdeb13-${DE}-live\n/" /etc/hosts

    # Autologin user
    cat << EOF > /etc/lightdm/lightdm.conf
[Seat:*]
autologin-user=${USER1}
autologin-user-timeout=0
EOF

}


    ########################################
    # Username & password seeding function #
    ########################################
def_user_pass() {
    adduser "${USER1}" --disabled-password --gecos "Debian13-${DE}-Live"
    echo "${USER1}:${PASS1}" | chpasswd
    usermod -aG sudo "${USER1}"
}

    ##########################
    # Customize user desktop #
    ##########################
    # Create skeleton dir to load for user
    mkdir -p /etc/skel

    # Customize .bashrc
    cat << 'SKEL_EOF' >> /etc/skel/.bashrc


#################################

# Live CD/USB Customizations

# Colour variables
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'

NC='\033[0m' # No color (reset)

# Welcome message in ascii art
echo && echo && toilet -f smblock -w 80 -F metal "\$USER"
echo
echo "=========================================="
sensors | grep Core | cut -c 1-23
sensors | grep in0
echo "=========================================="
echo -e "\${BLUE}IP Address:\${NC} \$(hostname -I)"
echo

# Force password entry in terminal for gpg variable
export GPG_TTY=\$(tty)

# Colour in man pages
export LESS_TERMCAP_mb=\$'\e[01;31m'    # blinking (used for headings)
export LESS_TERMCAP_md=\$'\e[01;36m'    # bold (cyan)
export LESS_TERMCAP_me=\$'\e[0m'        # reset mode
export LESS_TERMCAP_so=\$'\e[01;44;37m' # standout (white on blue, used for search matches)
export LESS_TERMCAP_se=\$'\e[0m'        # end standout
export LESS_TERMCAP_us=\$'\e[01;32m'    # underlined (green)
export LESS_TERMCAP_ue=\$'\e[0m'        # end underline
export GROFF_NO_SGR=1                   # prevents issues in some terminals

# Enable bash_functions file
if [[ -f ~/.bash_functions ]]; then
    source ~/.bash_functions
fi


###########################
# nnn file manager config #
###########################

# See homepage for keybindings & other custom settings:
# https://github.com/jarun/nnn/

# Default text editor
# For editing files in sudo, run 'sudo nnn "-eocHi"', select file & open with (o) nano.
export VISUAL=nano
export EDITOR=nano

# cd on quit
n () {
    # Block nesting of nnn in subshells
    [ "\${NNNLVL:-0}" -eq 0 ] || {
        echo "nnn is already running"
        return
    }

    # The behaviour is set to cd on quit (nnn checks if NNN_TMPFILE is set)
    # If NNN_TMPFILE is set to a custom path, it must be exported for nnn to
    # see. To cd on quit only on ^G, remove the "export" and make sure not to
    # use a custom path, i.e. set NNN_TMPFILE *exactly* as follows:
    export NNN_TMPFILE="\${XDG_CONFIG_HOME:-\$HOME/.config}/nnn/.lastd"

    # The command builtin allows one to alias nnn to n, if desired, without
    # making an infinitely recursive alias
    command nnn "-eocHi"

    [ ! -f "\$NNN_TMPFILE" ] || {
        . "\$NNN_TMPFILE"
        rm -f -- "\$NNN_TMPFILE" > /dev/null
    }
}
SKEL_EOF

    # Customize .bash_aliases
    cat << 'SKEL2_EOF' > /etc/skel/.bash_aliases
# My Live CD/USB aliases
alias bash_history='nano ~/.bash_history'
alias bash_aliases='nano ~/.bash_aliases'
alias bashrc='nano ~/.bashrc'
alias l='eza --icons -a'
alias ll='ls -lah'
alias lsl='eza --tree --icons --level=2 -la'
alias duf='duf --hide-mp /var/log,/var/log.hdd,/run/lock,/run/user/1000'
alias ih='unset HISTFILE'
alias rsync='rsync -r --stats --info=progress2'
alias sn='sudo nnn "-eocHi"'
alias sd='sudo shutdown now'
alias lsblk='lsblk -e 179'
SKEL2_EOF

    # Add personal folders to user home
    #mkdir -p /etc/skel/{my_custom_folders_here}

    # Set correct permissions in skel dir
    chmod -R 755 /etc/skel
    chmod 644 /etc/skel/{.bash_aliases,.bashrc}

    # Execute password functions
    def_user_pass

    # Execute based on desktop environment selection
    case "${DE}" in
        "CLI") setup_cli ;;
        "KDE") setup_kde ;;
        "GNOME") setup_gnome ;;
        "MATE") setup_mate ;;
        "XFCE") setup_xfce ;;
    esac

    # Add plymouth boot splash
    install_plymouth

    # Setup locales (default US English)
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen en_US.UTF-8
    echo 'LANG=en_US.UTF-8' > /etc/default/locale
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en

    # Install & configure required nerd fonts for terminal icons support
    # These fonts provide wide support for most terminals
    apt install fontconfig fonts-noto-color-emoji -y -q
    mkdir -p /usr/local/share/fonts
    cd /usr/local/share/fonts
    curl -L "$NERD_DEJAVU" | tar xJ --exclude='*.txt' --exclude='*.md' \
        || { echo "✗ Dejavu font failed to install. Check URL."; }
    curl -L "$NERD_JETBRAINS" | tar xJ --exclude='*.txt' --exclude='*.md' \
        || { echo "✗ Jetbrains font failed to install. Check URL."; }
    curl -L "$NERD_ROBOTO" | tar xJ --exclude='*.txt' --exclude='*.md' \
        || { echo "✗ Roboto font failed to install. Check URL."; }

    # Update font cache
    fc-cache -fv 2>&1


    #######################
    # Memory Optimization #
    #######################

    # Optimize for 8GB RAM system
    cat > /etc/sysctl.d/99-live-optimize.conf << 'SYSCTL_EOF'
# Reduce memory pressure for live system
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5

# Optimize for USB removal after toram
kernel.nmi_watchdog=0
SYSCTL_EOF

    # Configure tmpfs size limits
    cat > /etc/fstab << 'FSTAB_EOF'
# RAM-based filesystems for live environment
tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,size=1G 0 0
tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,size=100M 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,size=500M 0 0
FSTAB_EOF

    # Disable unnecessary services to save RAM
    systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    systemctl disable man-db.timer 2>/dev/null || true
    systemctl disable fstrim.timer 2>/dev/null || true

    # Configure zram swap for extra memory headroom
    apt install zram-tools -y -q
    cat > /etc/default/zramswap << 'ZRAM_EOF'
# ZRAM configuration for 8GB system
ALGO=zstd
PERCENT=25  # Use 25% of RAM for compressed swap (2GB)
PRIORITY=100
ZRAM_EOF


    ################################
    # Startup and shutdown scripts #
    ################################

    mkdir -p /etc/systemd/system

    # Service flag to mark a toram boot (can be used by other units)
    cat > /etc/systemd/system/toram-flag.service << 'TORAM_FLAG_EOF'
[Unit]
Description=Mark toram boot
ConditionKernelCommandLine=toram
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'touch /run/toram-active'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
TORAM_FLAG_EOF

    # Unmount of the live medium once toram boot has fully settled.
    # Harmless if the medium is already gone.
    cat > /usr/local/bin/toram-cleanup << 'TORAM_CLEANUP_SCRIPT'
#!/bin/sh
# /usr/local/bin/toram-cleanup
[[ -f /run/toram-active ]] || exit 0

# Try to unmount the live medium if it's still mounted
if mountpoint -q /run/live/medium 2>/dev/null; then
    umount -l /run/live/medium 2>/dev/null || true
fi
exit 0
TORAM_CLEANUP_SCRIPT

    # Make executable
    chmod +x /usr/local/bin/toram-cleanup

    # Create service to run script
    cat > /etc/systemd/system/toram-cleanup.service << 'SERVICE_EOF'
[Unit]
Description=Cleanup after toram load
After=local-fs.target
ConditionKernelCommandLine=toram

[Service]
Type=oneshot
ExecStart=/usr/local/bin/toram-cleanup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    # Enable services
    systemctl enable toram-flag.service
    systemctl enable toram-cleanup.service

    #################
    # Final cleanup #
    #################

    apt autoclean -y -q 2>&1
    apt autoremove -y -q 2>&1
    rm -rf /tmp/* 2>&1
    echo > /root/.bash_history 2>&1
SCRIPT_EOT


# Clear sensitive variables after chroot completes
unset PASS1 USER1 CHRUSER1

# Execute building live CD iso
unmount_vfs
build_iso

#################
# END OF SCRIPT #
#################
