#!/bin/bash

VRS=v3.02

# Changelog:
# Updated DE package lists, changed boot parameters (toram), memory optimization for 8gb systems, corrected execution order (skel-->user/pass-->DE),
# re-added settings to: bash_aliases & bashrc, added unmount_vfs to exit (after chroot user customizations), add personal folder/files to skel (before user/pass),
# updated welcome message, added warning/error/success emojis, added Gnome DE, boot menu enhancements, boot_iso function rewrite,
# disabled laptop lid suspend on cli DE, cosmetic tweaks, added plymouth boot themes, changed menu style, added welcome message countdown timer,
# added env_updates function & cleaned up logic flow.


# Full ANSI colors list
WHITE="\e[97m"
BLACK="\e[30m"
GRAY="\e[90m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"

LIGHT_GRAY="\e[37m"
LIGHT_RED="\e[91m"
LIGHT_GREEN="\e[92m"
LIGHT_YELLOW="\e[93m"
LIGHT_BLUE="\e[94m"
LIGHT_MAGENTA="\e[95m"
LIGHT_CYAN="\e[96m"

BOLD="\e[1m"
FAINT="\e[2m"
ITALICS="\e[3m"
UNDERLINE="\e[4m"
FLASHING="\e[5m"
FLASHING2="\e[6m"
INVISIBLE="\e[7m"
THROUGH-LINE="\e[9m"

# No Color (reset)
NC='\033[0m'

# Call local user & export home directory variable
if [ -n "$SUDO_USER" ]; then
    BUILDF="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    echo -e "${RED}⚠️  Error:${NC} This script must be run with sudo\n"
    exit 1
fi

# Make working path available for script build
export BUILDF

# Welcome message banner
clear
echo -e "\n${YELLOW}══════════════════════════════════════════════════════${NC}"
echo -e "\n${YELLOW}${BOLD}   <<  Custom Live CD/USB build script ${VRS}  >>${NC}\n"
echo -e "Script to build a bootable Live CD/USB using x64 Debian 13"
echo -e "with a choice of custom desktop environments.\n"
echo -e " - System changes will be irreversibly lost after reboot"
echo -e " - Chroot customization during build"
echo -e " - Choice to load part or all the filesystem into RAM on"
echo -e "   boot (all to RAM or system read-only & changes to RAM)"
echo -e " - RAM optimized\n"
echo -e "${UNDERLINE}${CYAN}Note:${NC} Loading the entire filesystem to RAM increases"
echo -e "performance but at the cost of using more RAM space (not"
echo -e "recommended for systems with 8GB RAM or less).\n\n"


# Message countdown variable
count_message=20

# Skip welcome message banner loop
while [[ $count_message -gt 0 ]]; do
    echo -ne "\r${CYAN}This screen will clear in${NC} ${BLUE}$count_message${NC} ${CYAN}second[s].${NC} Press any key to skip... "
    if read -t 1 -n 1 -s key; then
        break
        clear
    fi

    # Decrement the counter
    ((count_message--))
done

clear


# Uncomment this section to enable logging
#LOG_FILE="live-build.log"
#exec > >(tee -a "$LOG_FILE") 2>&1
#echo "######################################################"
#echo -e "Live bash script output will go to $LOG_FILE"
#echo -e "\t$(date "+%Y-%m-%d %H:%M:%S")"
#echo "######################################################"


##########################
# Declare main functions #
##########################
# Select target desktop environment
env_select () {
    echo -e "\n═════════════════════════════════════════════════════════"
    echo -e "${YELLOW}Choose target desktop environment for Live CD/USB build${NC}"
    echo -e "═════════════════════════════════════════════════════════\n"
    echo -e "  ${BLUE}1)${NC} ${CYAN}CLI${NC} - Command Line Interface only (no GUI)"
    echo -e "  ${BLUE}2)${NC} ${CYAN}KDE${NC} - KDE Plasma Desktop"
    echo -e "  ${BLUE}3)${NC} ${CYAN}GNOME${NC} - GNOME Desktop"
    echo -e "  ${BLUE}4)${NC} ${CYAN}MATE${NC} - MATE Desktop (Classic GNOME)"
    echo -e "  ${BLUE}5)${NC} ${CYAN}XFCE${NC} - XFCE Lightweight Desktop"
    echo -e "  ${BLUE}6)${NC} ${BLUE}Exit${NC} - Cancel and Exit Script\n"

    while true; do
        read -p "Enter choice [1-6]: " DE_NUM

        if [[ "$DE_NUM" == "6" ]]; then
            echo -e "${BLUE}No desktop environment selected. Script will exit.${NC}"
            exit 1
        elif [[ "$DE_NUM" =~ ^[1-5]$ ]]; then
            case $DE_NUM in
                1) DE=CLI ;;
                2) DE=KDE ;;
                3) DE=GNOME ;;
                4) DE=MATE ;;
                5) DE=XFCE ;;
                6) DE=HYPR ;;
            esac
            echo -e "\n${CYAN}'$DE'${NC} environment selected.\n"
            break
        else
            echo -e "${RED}✗ Invalid selection.${NC} Please choose a number from the list [1-7]."
        fi
    done
}

# Choices after previous DE build is found function
env_update () {
    echo -e "\n═════════════════════════════════════════════════════════"
    echo -e "${YELLOW}Existing live CD build folder found.${NC} Please select${NC}"
    echo -e "═════════════════════════════════════════════════════════\n"
    echo -e "  ${BLUE}1)${NC} ${CYAN}Rebuild Live CD/USB iso${NC} - Reauthor iso"
    echo -e "  ${BLUE}2)${NC} ${CYAN}Delete target build folder${NC} - Remove workspace"
    echo -e "  ${BLUE}3)${NC} ${CYAN}Chroot into target build${NC} - Make custom changes"
    echo -e "  ${BLUE}4)${NC} ${BLUE}Exit${NC} - Cancel and Exit Script\n"

    while [[ -d $BUILDF/LIVE_BOOT/$DE ]]; do
        read -p "Enter choice [1-4]: " CHOICE_NUM1

        if [[ "$CHOICE_NUM1" == "4" ]]; then
            echo -e "${BLUE}Script will exit."
            exit 1
        elif [[ "$CHOICE_NUM1" == "2" ]]; then
            echo -e "\n${RED}⚠️  Warning:${NC} $DE build folders & files will be permanently deleted."
            read -p "Are you sure? [y/n] " DEL_RESPONSE1
            if [[ "${DEL_RESPONSE1,,}" == "n" ]]; then
                echo -e "${BLUE}Deletion cancelled.${NC}\n"
            elif [[ "${DEL_RESPONSE1,,}" == "y" ]]; then
                unmount_vfs # Unmount virtual filesystems if mounted
                echo -e "${BLUE}$DE folder deleting...${NC}"
                rm -rf $BUILDF/LIVE_BOOT/$DE
                echo -e "${GREEN}✓ $DE build folder deleted. Script will exit.${NC}\n"
                exit 1
            else
                echo -e "${RED}✗ Invalid selection.${NC} Please choose a number from the list [1-4]."
            fi
        elif [[ $CHOICE_NUM1 == "1" ]]; then
            echo -e "\n${CYAN}'$DE'${NC} Live CD/USB iso will be recreated from existing build....\n"
            echo -e "${BLUE}Rebuilding iso...${NC}"
            unmount_vfs # Unmount virtual filesystems
            rm -rf /$BUILDF/LIVE_BOOT/$DE/chroot/tmp/* 2>/dev/null # Clear tmp dir
            build_iso # Rebuild iso
        elif [[ $CHOICE_NUM1 == "3" ]]; then
            chroot_access # Interactive chroot session
        else
            echo -e "${RED}✗ Invalid selection.${NC} Please choose a number from the list [1-4]."
        fi
    done
}


# Create username & password before build
preseed_user_pass () {
    echo -e "═════════════════════════════════════════════════════════\n"
    echo -e "${YELLOW}Create account username${NC}"
    read -p "(sudo enabled & root account disabled): " USER1
    echo -e "\n${CYAN}'$USER1'${NC} created"
    echo

    # Initialize attempt counter
    attempts=0
    max_attempts=3

    # Loop for password input and confirmation
    while [[ $attempts -lt $max_attempts ]]; do
        read -sp "Enter password for '$USER1': " PASS1
        #read -sp "" PASS1
        echo
        read -sp "Confirm password: " PASS2
        echo
        if [[ "$PASS1" == "$PASS2" ]]; then
            echo -e "${GREEN}✓ Password confirmed.\n${NC}"
            break
        else
            ((attempts++))
            if [[ $attempts -lt $max_attempts ]]; then
                echo -e "${RED}✗ Password does not match.${NC} You have $((max_attempts - attempts)) attempt[s] left.\n"
            else
                echo -e "${RED}✗ Password does not match. Maximum attempts reached. Script will exit.${NC}\n"
                exit 1
            fi
        fi
    done
}

# Unmount virtual filesystems
unmount_vfs () {
    echo -e "${BLUE}Unmounting chroot virtual filesystems...${NC}"
    if mountpoint -q $BUILDF/LIVE_BOOT/$DE/chroot/proc; then
        umount $BUILDF/LIVE_BOOT/$DE/chroot/proc 2>/dev/null
    fi
    if mountpoint -q $BUILDF/LIVE_BOOT/$DE/chroot/sys; then
        umount $BUILDF/LIVE_BOOT/$DE/chroot/sys 2>/dev/null
    fi
    if mountpoint -q $BUILDF/LIVE_BOOT/$DE/chroot/dev/pts; then
        umount $BUILDF/LIVE_BOOT/$DE/chroot/dev/pts 2>/dev/null
    fi
    if mountpoint -q $BUILDF/LIVE_BOOT/$DE/chroot/dev; then
        umount $BUILDF/LIVE_BOOT/$DE/chroot/dev 2>/dev/null
    fi
}

# Interactive chroot access
chroot_access () {
    # Mount necessary virtual filesystems
    if ! mountpoint -q $BUILDF/LIVE_BOOT/$DE/chroot/proc; then
        mount --bind /proc $BUILDF/LIVE_BOOT/$DE/chroot/proc 2>/dev/null
    fi
    if ! mountpoint -q $BUILDF/LIVE_BOOT/$DE/chroot/sys; then
        mount --bind /sys $BUILDF/LIVE_BOOT/$DE/chroot/sys 2>/dev/null
    fi
    if ! mountpoint -q $BUILDF/LIVE_BOOT/$DE/chroot/dev; then
        mount --bind /dev $BUILDF/LIVE_BOOT/$DE/chroot/dev 2>/dev/null
    fi
    if ! mountpoint -q $BUILDF/LIVE_BOOT/$DE/chroot/dev/pts; then
        mount --bind /dev/pts $BUILDF/LIVE_BOOT/$DE/chroot/dev/pts 2>/dev/null
    fi

    # Copy resolv.conf for network access in chroot
    cp /etc/resolv.conf $BUILDF/LIVE_BOOT/$DE/chroot/etc/

    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${BLUE}Entering chroot environment${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "${CYAN}You are now inside the ${DE} chroot.${NC}"
    echo -e "${CYAN}Make any desired changes to the system.${NC}"
    echo -e "${CYAN}Type 'exit' or <Ctrl+D> when finished to continue build.${NC}"
    echo -e "${BLUE}=========================================================${NC}\n"

    # Find target username & export variables for the chroot session
    CHRUSER1=$(ls -1d $BUILDF/LIVE_BOOT/$DE/chroot/home/*/ | xargs -n 1 basename)
    export DE CHRUSER1

    # Enter chroot interactively
    chroot $BUILDF/LIVE_BOOT/$DE/chroot /bin/bash

    # Capture the chroot exit status
    CHROOT_EXIT=$?

    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${GREEN}Exited chroot environment${NC}"
    echo -e "${BLUE}=========================================================${NC}\n"

    # Check if user wants to abort or continue iso build
    if [ $CHROOT_EXIT -eq 0 ]; then
        echo -e "\n═════════════════════════════════════════════════════════"
        echo -e "${YELLOW}Choose from the following options${NC}"
        echo -e "═════════════════════════════════════════════════════════\n"
        echo -e "  ${BLUE}1)${NC} ${CYAN}Rebuild Live CD/USB iso${NC} - Reauthor iso"
        echo -e "  ${BLUE}2)${NC} ${BLUE}Exit${NC} - Cancel and Exit Script"
        echo -e "\n${GRAY}<< Press any other key to return to previous menu >>${NC}\n"

        read -p "Enter choice [1-2]: " CHOICE_NUM2

        if [[ "$CHOICE_NUM2" == "2" ]]; then
            unmount_vfs
            echo -e "${BLUE}Script will exit.${NC}\n"
            exit 1
        elif [[ "$CHOICE_NUM2" == "1" ]]; then
            echo -e "${GREEN}Cleaning up and preparing workspace...${NC}"

	        # Perform any necessary cleanup inside chroot before building iso
            chroot $BUILDF/LIVE_BOOT/$DE/chroot /bin/bash << CHR_EOL
apt autoclean -y && apt autoremove -y # Clean up diskspace
rm -rf /tmp/* 2>/dev/null # Clear tmp dir
# Delete bash history
echo > /root/.bash_history
[ -f /home/${CHRUSER1}/.bash_history ] && echo > /home/${CHRUSER1}/.bash_history
CHR_EOL
            unmount_vfs # Unmount virtual filesystems
            build_iso # Rebuild iso
        else
            echo -e "Returning to previous menu...\n"
            env_update
        fi
    else
        echo -e "${RED}✗ Chroot session ended with errors or user abort.${NC}\n"
        exit 1
    fi
}

# Build iso function
build_iso () {
    # Directories for live environment files
    mkdir -p $BUILDF/LIVE_BOOT/$DE/{staging/{EFI/BOOT,boot/grub/{x86_64-efi,themes/debian13},isolinux,live},tmp}

    # Check and remove previous squash & iso, if found
    shopt -s nullglob
    iso_files=( "$BUILDF/LIVE_BOOT/$DE"/*.iso )
    sha_files=( "$BUILDF/LIVE_BOOT/$DE"/*.sha256sum )

    if [[ ${#iso_files[@]} -gt 0 || ${#sha_files[@]} -gt 0 ]]; then
        rm -f "${iso_files[@]}" "${sha_files[@]}" "$BUILDF/LIVE_BOOT/$DE/staging/live/filesystem.squashfs" 2>/dev/null
        echo -e "${BLUE}\nPrevious squash, iso, and/or checksum files deleted.${NC}\n"
    fi

    # Compress filesystem
    echo -e "${BLUE}Compressing filesystem...${NC}"
    mksquashfs $BUILDF/LIVE_BOOT/$DE/chroot $BUILDF/LIVE_BOOT/$DE/staging/live/filesystem.squashfs -e boot -comp xz -Xbcj x86 -b 1M
    cp $BUILDF/LIVE_BOOT/$DE/chroot/boot/vmlinuz-* $BUILDF/LIVE_BOOT/$DE/staging/live/vmlinuz
    cp $BUILDF/LIVE_BOOT/$DE/chroot/boot/initrd.img-* $BUILDF/LIVE_BOOT/$DE/staging/live/initrd

    ###########################################
    # ISOLINUX Configuration (BIOS/Legacy)    #
    ###########################################

    cat > $BUILDF/LIVE_BOOT/$DE/staging/isolinux/isolinux.cfg << 'ISOLINUX_EOF'
# Enable graphical menu
UI vesamenu.c32

# Menu appearance
MENU TITLE Debian 13 Live CD/USB Boot Menu
MENU BACKGROUND splash.png
MENU RESOLUTION 800 600

# Modern Blue Theme (for dark backgrounds)
MENU COLOR title        1;36;44    #ff8c00ff #00000000 std   # Orange title
MENU COLOR border       30;44      #00000000 #00000000 none  # Invisible border
MENU COLOR screen       37;40      #e0e1ddff #00000000 std   # Light gray text
MENU COLOR sel          7;37;40    #ffffffff #0077b6ff all   # White text on medium blue
MENU COLOR unsel        37;44      #adb5bdff #00000000 std   # Medium gray unselected
MENU COLOR disabled     30;44      #6c757dff #00000000 std   # Dark gray disabled
MENU COLOR help         1;33;40    #ffd166ff #00000000 std   # Warm yellow help
MENU COLOR msg07        37;40      #ced4daff #00000000 std   # Light gray messages
MENU COLOR scrollbar    30;44      #495057ff #00000000 std   # Medium dark scrollbar
MENU COLOR tabmsg       31;40      #48cae4ff #00000000 std   # Light blue tab
MENU COLOR timeout      1;37;40    #ef476fff #00000000 std   # Bright red timeout
MENU COLOR timeout_msg  1;33;40    #ffd166ff #00000000 std   # Warm yellow timeout msg
MENU COLOR cmdmark      1;36;40    #00b4d8ff #00000000 std   # Cyan command marker
MENU COLOR cmdline      37;40      #f8f9faff #00000000 std   # Off-white command line

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
TIMEOUT 150
MENU AUTOBOOT Starting in # second{,s}...

MENU SEPARATOR

LABEL linux-toram
  MENU LABEL ^1. Debian 13 Live - Load all to RAM [Remove USB]
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

    cat > $BUILDF/LIVE_BOOT/$DE/staging/boot/grub/grub.cfg << 'GRUB_EOF'
# Load GRUB modules
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod all_video
insmod font
insmod gfxterm
insmod gfxmenu
#insmod png
insmod gettext
insmod gzio

# Set graphics mode
set gfxmode=1024x768,800x600,640x480
set gfxpayload=keep
terminal_output gfxterm

# Load fonts and theme
loadfont unicode
set locale_dir=$prefix/locale
set lang=en_US

# Theme colors
set menu_color_normal=cyan/blue
set menu_color_highlight=white/blue
set color_normal=yellow/blue
set color_highlight=white/blue

# Boot menu appearance
set timeout=15
set default="0"
set menu_title="Debian 13 Live CD/USB Boot Menu"

menuentry "Debian 13 Live - Load to RAM [Remove USB]" --class debian {
    search --no-floppy --set=root --label DEB13-LIVE
    linux ($root)/live/vmlinuz boot=live toram toram=filesystem.squashfs quiet splash plymouth.enable=1
    initrd ($root)/live/initrd
    echo "Loading squashfs into RAM."
    echo "USB can be removed after boot..."
}

menuentry "Debian 13 Live - Normal Boot [Keep USB]" --class debian {
    search --no-floppy --set=root --label DEB13-LIVE
    linux ($root)/live/vmlinuz boot=live quiet splash plymouth.enable=1
    initrd ($root)/live/initrd
    echo "Loading changes into RAM (filesystem read-only)."
    echo "USB must remain connected..."
}

menuentry "Debian 13 Live - Safe Graphics Mode" --class debian {
    search --no-floppy --set=root --label DEB13-LIVE
    linux ($root)/live/vmlinuz boot=live toram nomodeset
    initrd ($root)/live/initrd
    echo "Loading with safe graphics mode..."
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
        initrd ($root)/live/initrd
    }
}

menuentry "Reboot System" {
    reboot
}

menuentry "Shutdown System" {
    halt
}
GRUB_EOF

    ###########################################
    # Generate Background Images              #
    ###########################################

    echo -e "${BLUE}Generating background images...${NC}"

    # Install imagemagick if needed
    if ! command -v convert &> /dev/null; then
        echo -e "${YELLOW}Installing ImageMagick...${NC}"
        apt install imagemagick -y 2>/dev/null || {
            echo -e "${RED}Failed to install ImageMagick. Skipping background images.${NC}"
        }
    fi

    # Generate backgrounds only if convert is available
    if command -v convert &> /dev/null; then

        #########################################
        # ISOLINUX Background (640x480)         #
        #########################################

        # Compatible background for most systems (use as fallback if running into issues)
        # Must be 640x480, 16 colors max, PNG format
        #convert -size 640x480 \
        #    gradient:'#2c3e50'-'#1a252f' \
        #    -colors 14 \
        #    -type truecolor \
        #    PNG8:"$BUILDF/LIVE_BOOT/$DE/staging/isolinux/splash.png" 2>/dev/null

        # Plain gradient background
        convert -size 640x480 \
            gradient:'#1a1a2e'-'#16213e' \
            "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/splash.png" 2>/dev/null && \
        convert $BUILDF/LIVE_BOOT/$DE/staging/isolinux/splash.png \
            -colors 16 -resize 640x480! \
            "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/splash.png" 2>/dev/null && \

        # Solid dark blue background (use as fallback if running into issues)
        #convert -size 640x480 xc:'#1a1a2e' \
            #"$BUILDF/LIVE_BOOT/$DE/staging/isolinux/splash.png" 2>/dev/null && \

        # Verify ISOLINUX background
        if [ -f "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/splash.png" ]; then
            echo -e "${GREEN}✓ ISOLINUX background created${NC}"
        else
            echo -e "${RED}✗ ISOLINUX background failed - creating fallback${NC}"
            # Fallback: solid color
            convert -size 640x480 xc:'#1a252f' -colors 14 \
                PNG8:"$BUILDF/LIVE_BOOT/$DE/staging/isolinux/splash.png" 2>/dev/null
        fi

        #########################################
        # GRUB Background (1024x768)            #
        #########################################

        # Clean GRUB-compatible background
        convert -size 1024x768 \
            gradient:'#1a252f'-'#2c3e50' \
            -interlace none \
            -type truecolor \
            -depth 24 \
            -define png:color-type=2 \
            -define png:bit-depth=8 \
            "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/themes/debian13/background.png" 2>/dev/null

        # Alternative fallback: Simple solid color (most compatibility)
        #convert -size 1024x768 \
        #     xc:'#1a252f' \
        #     -interlace none \
        #     -type truecolor \
        #     -depth 24 \
        #     -define png:color-type=2 \
        #     "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/themes/debian13/background.png" 2>/dev/null

        # Verify GRUB background
        if [ -f "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/themes/debian13/background.png" ]; then
            # Check if PNG is valid for GRUB
            if identify "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/themes/debian13/background.png" &>/dev/null; then
                echo -e "${GREEN}✓ GRUB background created${NC}"
            else
                echo -e "${RED}✗ GRUB background corrupted - creating fallback${NC}"
                # Fallback: minimal PNG
                convert -size 1024x768 xc:'#1a252f' \
                    -interlace none -type truecolor -depth 24 \
                    -define png:color-type=2 \
                    "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/themes/debian13/background.png" 2>/dev/null
            fi
        else
            echo -e "${RED}✗ GRUB background failed${NC}"
        fi

    else
        echo -e "${YELLOW}ImageMagick not available, skipping background generation${NC}"
    fi

    ###########################################
    # Copy Bootloader Files                   #
    ###########################################

    # Copy ISOLINUX files
    cp /usr/lib/ISOLINUX/isolinux.bin "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/"
    cp /usr/lib/syslinux/modules/bios/* "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/"

    # Verify vesamenu.c32 was copied
    if [ ! -f "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/vesamenu.c32" ]; then
        echo -e "${RED}ERROR: vesamenu.c32 not found! Searching...${NC}"
        find /usr -name "vesamenu.c32" -exec cp {} "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/" \; 2>/dev/null
    fi

    # Copy GRUB EFI files
    cp -r /usr/lib/grub/x86_64-efi/* "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/x86_64-efi/"

    # Copy memtest86+ if available
    if [ -f /boot/memtest86+.bin ]; then
        cp /boot/memtest86+.bin "$BUILDF/LIVE_BOOT/$DE/staging/live/"
    else
        echo -e "${YELLOW}Memtest86+ not found, skipping...${NC}"
        touch "$BUILDF/LIVE_BOOT/$DE/staging/live/memtest86+.bin"
    fi

    ###########################################
    # Create EFI Boot Images                  #
    ###########################################

    # Copy grub.cfg to EFI directory
    cp "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/grub.cfg" "$BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/"

    # Boot configuration for EFI
    cat > "$BUILDF/LIVE_BOOT/$DE/tmp/grub-embed.cfg" <<'EOF'
if ! [ -d "$cmdpath" ]; then
    if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "$cmdpath"; then
        cmdpath="${isodevice}/EFI/BOOT"
    fi
fi
configfile "${cmdpath}/grub.cfg"
EOF

    # Generate EFI bootable images
    grub-mkstandalone -O i386-efi \
        --modules="part_gpt part_msdos fat iso9660 all_video png" \
        --locales="" --themes="" --fonts="" \
        --output="$BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/BOOTIA32.EFI" \
        "boot/grub/grub.cfg=$BUILDF/LIVE_BOOT/$DE/tmp/grub-embed.cfg"

    grub-mkstandalone -O x86_64-efi \
        --modules="part_gpt part_msdos fat iso9660 all_video png" \
        --locales="" --themes="" --fonts="" \
        --output="$BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/BOOTx64.EFI" \
        "boot/grub/grub.cfg=$BUILDF/LIVE_BOOT/$DE/tmp/grub-embed.cfg"

    # Create UEFI boot disk image
    cd "$BUILDF/LIVE_BOOT/$DE/staging" && \
    dd if=/dev/zero of=efiboot.img bs=1M count=20 && \
    mkfs.vfat efiboot.img && \
    mmd -i efiboot.img ::/EFI ::/EFI/BOOT && \
    mcopy -vi efiboot.img \
        "$BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/BOOTIA32.EFI" \
        "$BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/BOOTx64.EFI" \
        ::/EFI/BOOT/ && \
    mcopy -vi efiboot.img \
        "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/grub.cfg" \
        ::/EFI/BOOT/

    ###########################################
    # Generate Final ISO                      #
    ###########################################

    # Copy kernel files to boot directory
    cp -L "$BUILDF/LIVE_BOOT/$DE/chroot/boot/vmlinuz-"* "$BUILDF/LIVE_BOOT/$DE/staging/boot/vmlinuz" 2>/dev/null || \
    cp "$BUILDF/LIVE_BOOT/$DE/chroot/boot/vmlinuz-"* "$BUILDF/LIVE_BOOT/$DE/staging/boot/"

    cp -L "$BUILDF/LIVE_BOOT/$DE/chroot/boot/initrd.img-"* "$BUILDF/LIVE_BOOT/$DE/staging/boot/initrd" 2>/dev/null || \
    cp "$BUILDF/LIVE_BOOT/$DE/chroot/boot/initrd.img-"* "$BUILDF/LIVE_BOOT/$DE/staging/boot/"

    echo -e "${BLUE}Generating ISO image...${NC}"

    # Build the ISO
    xorriso -as mkisofs \
        -iso-level 3 \
        -o "$BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.iso" \
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
        "$BUILDF/LIVE_BOOT/$DE/staging/efiboot.img" \
        "$BUILDF/LIVE_BOOT/$DE/staging"

        # Generate SHA256 hash of iso
        echo -e "\n${BLUE}Generating iso hash, please wait.....${NC}"
        sha256sum "$BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.iso" > "$BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.sha256sum"

        # Set permissions
        chmod 644 "$BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.iso"
        chmod 644 "$BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.sha256sum"

        echo -e "${GREEN}✓ '${DE}' Live CD/USB build completed${NC}"
        echo -e "${CYAN}💿: $BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.iso${NC}\n"
        exit 1
}


#########################################
# Execute desktop environment selection #
#########################################
env_select

###############################################################
# Execute build update selection when previous build is found #
###############################################################

if [[ -d $BUILDF/LIVE_BOOT/$DE ]]; then
    env_update
fi

#############################################
# Execute pre-seed username & password loop #
#############################################
preseed_user_pass

###########################
# Build iso (initial run) #
###########################

echo -e "${BLUE}Starting Live CD/USB build...${NC}"

# Install prerequisite packages
apt install debootstrap squashfs-tools xorriso isolinux syslinux-efi grub-efi-amd64-bin grub-efi-ia32-bin mtools dosfstools -y

# Create workspace for building live environment
mkdir -p $BUILDF/LIVE_BOOT/$DE

# Clear problematic environment variables
unset CDPATH
unalias mkdir 2>/dev/null
unalias cd 2>/dev/null

# Bootstrap Debian 13 (trixie)
debootstrap --arch=amd64 --variant=minbase trixie $BUILDF/LIVE_BOOT/$DE/chroot http://ftp.us.debian.org/debian/

# Export variables for chroot
export DE USER1 PASS1

# Chroot into live build environment
chroot $BUILDF/LIVE_BOOT/$DE/chroot /bin/bash << SCRIPT_EOT
    chmod 1777 /tmp # Fix for 'permission denied' apt update error

    # Update sources.list
    cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian/ trixie main non-free-firmware non-free contrib
deb-src http://deb.debian.org/debian/ trixie main non-free-firmware non-free contrib
deb http://security.debian.org/debian-security trixie-security main non-free-firmware non-free contrib
deb-src http://security.debian.org/debian-security trixie-security main non-free-firmware non-free contrib
# trixie-updates
deb http://deb.debian.org/debian/ trixie-updates main non-free-firmware contrib
deb-src http://deb.debian.org/debian/ trixie-updates main non-free-firmware contrib
EOF

    # Mount system directories (if not already mounted)
    if ! mountpoint -q /proc; then
        mount none -t proc /proc
    fi
    if ! mountpoint -q /sys; then
        mount none -t sysfs /sys
    fi
    if ! mountpoint -q /dev/pts; then
        mount none -t devpts /dev/pts
    fi
    if ! mountpoint -q /dev; then
        mount none -t dev /dev
    fi

    # Exit script gracefully if errors encountered
    trap 'umount /proc 2>/dev/null; umount /sys 2>/dev/null; umount /dev/pts 2>/dev/null; umount /dev 2>/dev/null; exit' ERR EXIT

    apt update

    # Essential programs
    apt install linux-image-amd64 live-boot systemd-sysv -y

    #################################
    # Plymouth boot splash function #
    #################################
install_plymouth() {
    # Install plymouth
    DEBIAN_FRONTEND=noninteractive apt install plymouth plymouth-themes -y

    # Set default theme (uncomment to your preference)
    plymouth-set-default-theme spinner -R 2>/dev/null
    #plymouth-set-default-theme solar -R 2>/dev/null

    # Ensure plymouth is in initramfs
    echo "FRAMEBUFFER=y" > /etc/initramfs-tools/conf.d/plymouth

    # Update initramfs to include Plymouth
    update-initramfs -u -k all
}

    # Desktop environment setup:-->

    #################################
    # CLI (no gui, no xorg, no x11) #
    #################################
setup_cli() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install network-manager sudo nano gnupg zip unzip rar locales firmware-amd-graphics firmware-atheros amd64-microcode firmware-iwlwifi firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode wget exfat-fuse ntfs-3g lvm2 dosfstools mtools duf curl eza htop lm-sensors toilet figlet ssh sshfs parted screen rsync ufw git cryptsetup command-not-found xz-utils file manpages man-db lsof -y

    # Add your custom packages here
    # apt install fail2ban aria2 ... -y

    # Command line docx viewer
    cd /tmp
    curl -L https://github.com/bgreenwell/doxx/releases/latest/download/doxx-$(uname -s)-$(uname -m).tar.gz | tar xz
    chmod +x doxx && mv doxx /usr/local/bin/

    # cli file manager
    apt install nnn

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

    # Add plymouth boot splash
    install_plymouth
}

    ######################
    # KDE Plasma desktop #
    ######################
setup_kde() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install kde-plasma-desktop plasma-nm sddm sddm-theme-breeze kwin-addons dolphin konsole sudo nano git pipx gnupg dmsetup zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools ufw pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs ssh sshfs screen rsync qtqr ufw git cryptsetup command-not-found xz-utils file manpages man-db lsof -y

    # Add your custom packages here
    # apt install fail2ban aria2 ... -y

    # cli flie manager
    apt install nnn

    # Media, codecs, & graphics packages
    #apt install vlc intel-media-va-driver ffmpeg gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav -y

    # Office packages
    #apt install libreoffice-writer libreoffice-calc -y

    # Remove unwanted packages
    apt remove kdeconnect konqueror plasma-welcome khelpcenter* firefox* libreoffice-math -y

    # Brave web browser (resource useage heavy)
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    apt update && apt install brave-browser -y

    # Librewolf web browser (resource useage medium)
    #apt update && sudo apt install extrepo -y
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

    # Add plymouth boot splash
    install_plymouth
}

    #################
    # GNOME desktop #
    #################
setup_gnome() {
    # Essential gnome packages (minimal)
    DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends gnome-core gdm3 network-manager-gnome gedit -y

    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install sudo nano git pipx gnupg dmsetup zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools ufw pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs ssh sshfs screen rsync qtqr ufw git cryptsetup command-not-found xz-utils file manpages man-db lsof -y

    # Add your custom packages here
    # apt install fail2ban aria2 ... -y

    # cli file manager
    apt install nnn

    # Media, codecs, & graphics packages
    #apt install vlc intel-media-va-driver ffmpeg gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav -y

    # Office packages
    #apt install libreoffice-writer libreoffice-calc -y

    # Remove unwanted packages
    apt remove firefox* libreoffice-math -y

    # Brave web browser (resource useage heavy)
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    apt update && apt install brave-browser -y

    # Librewolf web browser (resource useage medium)
    #apt update && sudo apt install extrepo -y
    #extrepo enable librewolf && extrepo update librewolf
    #apt update && apt install librewolf -y

    # Falkon web browser (resource useage light)
    #apt install falkon -y

    # Printer packages
    #apt install cups system-config-printer foomatic-db openprinting-ppds tcl-tclreadline psutils -y
    #systemctl enable cups

    # Gnome shell extensions
    #apt install gnome-shell-extensions gnome-tweaks gnome-shell-extension-manager gnome-shell-extension-status-icons gnome-shell-extension-impatience gnome-shell-extension-freon gnome-shell-extension-desktop-icons-ng gnome-shell-extension-dashtodock gnome-shell-extension-caffeine gnome-shell-extension-blur-my-shell gnome-shell-extension-autohidetopbar -y

    # Initialize hostname
    echo "deb13-${DE}-live" > /etc/hostname
    sed -i "1s/^/127.0.0.1\tdeb13-${DE}-live\n/" /etc/hosts

    # Autologin user
    cat << EOF > /etc/gdm3/custom.conf
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${USER1}
EOF

    # Add plymouth boot splash
    install_plymouth
}

    ################
    # MATE desktop #
    ################
setup_mate() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install mate-desktop-environment-core lightdm mate-media pulseaudio pulseaudio-utils alsa-utils network-manager-gnome mate-power-manager upower acpid sudo nano git pipx gnupg dmsetup unrar rar zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools ufw pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs keepassxc xclip mousepad ssh sshfs screen rsync qtqr ufw git cryptsetup command-not-found xz-utils file manpages man-db lsof -y

    # Add your custom packages here
    # apt install fail2ban aria2 ... -y

    # cli file manager
    apt install nnn

    # Media, codecs, & graphics packages
    #apt install vlc intel-media-va-driver ffmpeg gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav -y

    # Office packages
    #apt install libreoffice-writer libreoffice-calc -y

    # Remove unwanted packages
    apt remove firefox* libreoffice-math -y

    # Brave web browser (resource useage heavy)
    #curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    #curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    #apt update && apt install brave-browser -y

    # Librewolf web browser (resource useage medium)
    apt update && sudo apt install extrepo -y
    extrepo enable librewolf && extrepo update librewolf
    apt update && apt install librewolf -y

    # Falkon web browser (resource useage light)
    #apt install falkon -y

    # Printer packages
    #apt install cups system-config-printer foomatic-db openprinting-ppds tcl-tclreadline psutils -y
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

    # Add plymouth boot splash
    install_plymouth
}

    ################
    # XFCE desktop #
    ################
setup_xfce() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install xfce4 xfce4-goodies lightdm network-manager-gnome sudo nano git pipx gnupg ssh dmsetup unrar rar zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools ufw pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs keepassxc xclip ssh sshfs screen rsync qtqr ufw git cryptsetup command-not-found xz-utils file manpages man-db lsof -y

    # Add your custom packages here
    # apt install fail2ban aria2 ... -y

    # cli file manager
    apt install nnn

    # Media, codecs, & graphics packages
    #apt install vlc intel-media-va-driver ffmpeg gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav -y

    # Office packages
    #apt install libreoffice-writer libreoffice-calc -y

    # Remove unwanted packages
    apt remove firefox* libreoffice-math -y

    # Brave web browser (resource useage heavy)
    #curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    #curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    #apt update && apt install brave-browser -y

    # Librewolf web browser (resource useage medium)
    #apt update && sudo apt install extrepo -y
    #extrepo enable librewolf && extrepo update librewolf
    #apt update && apt install librewolf -y

    # Falkon web browser (resource useage light)
    apt update && apt install falkon -y

    # Printer packages
    #apt install cups system-config-printer foomatic-db openprinting-ppds tcl-tclreadline psutils -y
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

    # Add plymouth boot splash
    install_plymouth
}

    #########################################
    # Username & password seeding functions #
    #########################################
def_user_pass() {
    adduser ${USER1} --disabled-password --gecos "Debian13-${DE}-Live"
    echo "${USER1}:changeme" | chpasswd
}

hashed_pass() {
    if ! command -v mkpasswd &> /dev/null; then
        apt install whois -y
    fi
    HASHP=$(mkpasswd -m sha-512 --stdin <<< "${PASS1}")
    usermod -p "${HASHP}" ${USER1}
    usermod -aG sudo ${USER1}
}

    ##########################
    # Customize user desktop #
    ##########################
    # Create skeleton dir to load for all users
    mkdir -p /etc/skel

    # Customize .bashrc
    cat << 'SKEL_EOF' >> /etc/skel/.bashrc


#################################

# Live CD/USB Customizations

# Colour variables
GREEN='\033[0;32m'
RED='\033[0;31m'
WHITE='\033[0;37m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
LIGHTGRAY='\033[0;37m'

RESET='\033[0m'

# Welcome message in ascii art
echo && echo && toilet -f smblock -w 80 -F metal "\$USER"
echo
echo "=========================================="
sensors | grep Core | cut -c 1-23
sensors | grep in0
echo "=========================================="
echo -e "\${BLUE}IP Address:\${RESET} \$(hostname -I)"
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
export GROFF_NO_SGR=1                  # prevents issues in some terminals

# Enable bash_functions file
if [[ -f ~/.bash_functions ]]; then
    source ~/.bash_functions
fi


###########################
# nnn file manager config #
###########################

# See homepage for keybindings & other custom settings:
# https://github.com/jarun/nnn/

# Export plugins
# Plugins enabled: file search (f), shell-friendly file renamer (n), access sudo permissions (s), give file executable permissions (p)
export NNN_PLUG='f:fzcd;n:fixname;s:suedit;p:!chmod +x "$nnn"*'

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
    cat << 'SKEL_EOF' > /etc/skel/.bash_aliases
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
SKEL_EOF

    # Add personal folders to user's home
    #mkdir -p /etc/skel/{your_custom_folders_here}

    # Set correct permissions in skel dir
    chmod -R 755 /etc/skel
    chmod 644 /etc/skel/{.bash_aliases,.bashrc}

    ##############################
    # Execute password functions #
    ##############################
    def_user_pass
    hashed_pass

    ##################################################
    # Execute based on desktop environment selection #
    ##################################################
    case "${DE}" in
        "CLI")
            setup_cli
            ;;
        "KDE")
            setup_kde
            ;;
        "GNOME")
            setup_gnome
            ;;
        "MATE")
            setup_mate
            ;;
        "XFCE")
            setup_xfce
            ;;
    esac

    # Setup locales (default US English)
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen en_US.UTF-8
    echo 'LANG=en_US.UTF-8' > /etc/default/locale
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en

    # Optional: Install & configure required fonts for terminal icons support
    # These fonts provide wide support for most terminals
    #apt install fontconfig -y
    #cd /tmp
    #mkdir -p /usr/local/share/fonts
    #wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/DejaVuSansMono.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/RobotoMono.zip
    #unzip DejaVuSansMono.zip  -x "*.txt" "*.md" -d /usr/local/share/fonts/
    #unzip JetBrainsMono.zip  -x "*.txt" "*.md" -d /usr/local/share/fonts/
    #unzip RobotoMono.zip  -x "*.txt" "*.md" -d /usr/local/share/fonts/
    #fc-cache -fv # Update font cache


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
    apt install zram-tools -y
    cat > /etc/default/zramswap << 'ZRAM_EOF'
# ZRAM configuration for 8GB system
ALGO=zstd
PERCENT=25  # Use 25% of RAM for compressed swap (2GB)
PRIORITY=100
ZRAM_EOF

    # Create pre-load script to notify when safe to remove USB
    cat > /usr/local/bin/usb-safe-remove << 'SAFE_SCRIPT'
#!/bin/bash

# Check if system is running from RAM
if grep -q "toram" /proc/cmdline; then
    echo "System is running from RAM. Safe to remove USB."
    echo "You can remove the boot media now."

    # Try to unmount USB if still mounted
    USB_MOUNT=$(mount | grep "/run/live/medium" | awk '{print $1}')
    if [ -n "$USB_MOUNT" ]; then
        umount /run/live/medium 2>/dev/null
    fi
else
    echo "⚠️  WARNING: System is NOT running from RAM!"
    echo "Do NOT remove the boot media!"
fi
SAFE_SCRIPT

    # Make script executable
    chmod +x /usr/local/bin/usb-safe-remove

    ####################################################
    # Automatically unmount USB after successful toram #
    ####################################################

    # Create systemd service for post-toram cleanup
    cat > /etc/systemd/system/toram-cleanup.service << 'SERVICE_EOF'
[Unit]
Description=Cleanup after toram load
After=local-fs.target
ConditionKernelCommandLine=toram

[Service]
Type=oneshot
ExecStart=/usr/local/bin/usb-safe-remove
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl enable toram-cleanup.service

    # Final cleanup
    apt autoclean -y && apt autoremove -y
    rm -rf /tmp/* 2>/dev/null
    echo > /root/.bash_history

    echo $$
SCRIPT_EOT

# Clear sensitive variables after chroot completes
unset PASS1 USER1 CHRUSER1

################################
# Execute building live CD iso #
################################
unmount_vfs
build_iso
exit 1

#################
# END OF SCRIPT #
#################
