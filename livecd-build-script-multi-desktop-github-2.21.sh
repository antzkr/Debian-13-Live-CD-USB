#!/bin/bash

# v2.21

######################################################################
# Script to build a bootable live CD / USB using Debian 13 x64 base  #
# with custom desktop environment. See readme for details.           #
#                                                                    #
# Credit to Will Haley for inspiring this script:                    #
# https://www.willhaley.com/blog/custom-debian-live-environment/     #
######################################################################


# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Reset
NC='\033[0m' # No Color


# Call local user & export home directory variable
if [ -n "$SUDO_USER" ]; then
    BUILDF="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    echo -e "${RED}Error:${NC} This script must be run with sudo"
    exit 1
fi
export BUILDF


echo -e "\n${CYAN}===================================================${NC}\n"
echo -e "${CYAN}Script to build a bootable live CD / USB using${NC}"
echo -e "${CYAN}Debian 13 x64 base with custom desktop environment.${NC}\n"
echo -e "${CYAN}Customizable. See readme for details.${NC}\n"
echo -e "${CYAN}===================================================${NC}\n"


# Pipe the output of running live script into a log file while
# keeping it visible on the console.
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
echo -e "\n${YELLOW}Choose target desktop environment for live build:${NC}\n"
PS3="Option: "
select DE in "CLI" "KDE" "MATE" "XFCE" "Exit"; do
    if [[ "$DE" == "Exit" ]]; then
        echo -e "${BLUE}No desktop environment selected. Script will exit here.${NC}\n"
        exit 1
    elif [[ -n "$DE" ]]; then
        echo -e "\n${CYAN}$DE${NC} environment selected\n"
        break
    else
        echo "Invalid selection. Please choose a number from the list."
    fi
done
}

# Create username & password before build
preseed_user_pass () {
echo
read -p "Create a username (sudo will be enabled & root account will be disabled): " USER1
echo -e "${CYAN}$USER1${NC} created"
echo

# Initialize attempt counter
attempts=0
max_attempts=3

# Loop for password input and confirmation
while [[ $attempts -lt $max_attempts ]]; do
    echo -e "\nEnter password for ${CYAN}$USER1${NC}: "
    read -sp "" PASS1
    read -sp "Confirm password: " PASS2
    echo
    if [[ "$PASS1" == "$PASS2" ]]; then
        echo -e "\n${GREEN}Password confirmed.${NC}"
        break
    else
        ((attempts++))
        if [[ $attempts -lt $max_attempts ]]; then
            echo -e "\n${RED}Password does not match.${NC} You have $((max_attempts - attempts)) attempts left.\n"
        else
            echo -e "\n${RED}Password does not match. Maximum attempts reached. Script will exit.${NC}\n"
            exit 1
        fi
    fi
done
}

# Unmount virtual filesystems
unmount_vfs () {
echo -e "${BLUE}Unmounting chroot virtual filesystems...${NC}\n"
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

echo -e "\n${CYAN}===============================================${NC}"
echo -e "${CYAN}Entering chroot environment${NC}"
echo -e "${CYAN}===============================================${NC}"
echo -e "${YELLOW}You are now inside the ${DE} chroot.${NC}"
echo -e "${YELLOW}Make any desired changes to the system.${NC}"
echo -e "${YELLOW}Type 'exit' when finished to continue build.${NC}"
echo -e "${CYAN}===============================================${NC}\n"

# Find target username & export variables for the chroot session
CHRUSER1=$(ls -1d $BUILDF/LIVE_BOOT/$DE/chroot/home/*/ | xargs -n 1 basename)
export DE CHRUSER1

# Enter chroot interactively
chroot $BUILDF/LIVE_BOOT/$DE/chroot /bin/bash

# Capture the chroot exit status
CHROOT_EXIT=$?

echo -e "\n${CYAN}===============================================${NC}"
echo -e "${CYAN}Exited chroot environment${NC}"
echo -e "${CYAN}===============================================${NC}\n"

# Check if user wants to abort or continue iso build loop
if [ $CHROOT_EXIT -eq 0 ]; then
    echo -e "\n${YELLOW}Choose from the following options:${NC}\n"
    PS3="Option: "
    select CHOICE2 in "Rebuild live CD iso" "Exit"; do
        if [[ "$CHOICE2" == "Exit" ]]; then
            echo -e "\n${BLUE}Script will exit.${NC}\n"
            exit 1
        elif [[ "$CHOICE2" == "Rebuild live CD iso" ]]; then
            echo -e "\n${GREEN}Cleaning up and preparing workspace...${NC}"

	    # Perform any necessary cleanup inside chroot before building iso
            chroot $BUILDF/LIVE_BOOT/$DE/chroot /bin/bash << EOL

apt autoclean -y && apt autoremove -y # Clean up diskspace

# Delete bash history
echo > /root/.bash_history
[ -f /home/${CHRUSER1}/.bash_history ] && echo > /home/${CHRUSER1}/.bash_history

# Housekeeping
locale-gen en_US.UTF-8 # Set locale if unset
rm -rf /tmp/* 2>/dev/null # Clear tmp dir
EOL
            unmount_vfs # Unmount virtual filesystems
            build_iso # Rebuild iso
        else
            echo "Invalid selection. Please choose a number from the list."
        fi
    done
else
    echo -e "${RED}Chroot session ended with errors or user abort.${NC}\n"
    exit 1
fi
}


# Build live iso
build_iso () {
    # Directories for live environment files
    mkdir -p $BUILDF/LIVE_BOOT/$DE/{staging/{EFI/BOOT,boot/grub/x86_64-efi,isolinux,live},tmp}

	# Enables the nullglob shell option. This ensures that if the wildcard patterns *.iso or *.sha256sum
	# don't match any files, the resulting arrays (iso_files, sha_files) will be empty instead of
	# containing the literal pattern string (e.g. *.iso)
    shopt -s nullglob
    iso_files=( "$BUILDF/LIVE_BOOT/$DE"/*.iso )
    sha_files=( "$BUILDF/LIVE_BOOT/$DE"/*.sha256sum )

    # Check and remove previous squash & iso, if found
    if [[ ${#iso_files[@]} -gt 0 || ${#sha_files[@]} -gt 0 ]]; then
        rm -f "${iso_files[@]}" "${sha_files[@]}" "$BUILDF/LIVE_BOOT/$DE/staging/live/filesystem.squashfs" 2>/dev/null
        echo -e "${BLUE}\nPrevious squash, iso, and/or checksum files deleted.${NC}\n"
    fi

    # Compress filesystem
    mksquashfs $BUILDF/LIVE_BOOT/$DE/chroot $BUILDF/LIVE_BOOT/$DE/staging/live/filesystem.squashfs -e boot
    cp $BUILDF/LIVE_BOOT/$DE/chroot/boot/vmlinuz-* $BUILDF/LIVE_BOOT/$DE/staging/live/vmlinuz
    cp $BUILDF/LIVE_BOOT/$DE/chroot/boot/initrd.img-* $BUILDF/LIVE_BOOT/$DE/staging/live/initrd

    # Bootloader menu (BIOS/legacy mode)
    cat > $BUILDF/LIVE_BOOT/$DE/staging/isolinux/isolinux.cfg << EOF
UI vesamenu.c32

MENU TITLE Boot Menu
DEFAULT linux
TIMEOUT 300
MENU RESOLUTION 640 480
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

LABEL linux
  MENU LABEL Debian 13 Live [BIOS/ISOLINUX]
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live

LABEL linux
  MENU LABEL Debian 13 Live [BIOS/ISOLINUX] (nomodeset)
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live nomodeset
EOF

    # Bootloader menu (EFI mode)
    cat > $BUILDF/LIVE_BOOT/$DE/staging/boot/grub/grub.cfg <<'EOF'
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod all_video
insmod font

set default="0"
set timeout=15

menuentry "Debian 13 Live [EFI/GRUB]" {
    search --no-floppy --set=root --label DEB13-LIVE
    linux ($root)/live/vmlinuz boot=live
    initrd ($root)/live/initrd
}

menuentry "Debian 13 Live [EFI/GRUB] (nomodeset)" {
    search --no-floppy --set=root --label DEB13-LIVE
    linux ($root)/live/vmlinuz boot=live nomodeset
    initrd ($root)/live/initrd
}
EOF

    # Copy grub into workspace
    cp $BUILDF/LIVE_BOOT/$DE/staging/boot/grub/grub.cfg $BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/

    # Boot configuration
    cat > $BUILDF/LIVE_BOOT/$DE/tmp/grub-embed.cfg <<'EOF'
if ! [ -d "$cmdpath" ]; then
    if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "$cmdpath"; then
        cmdpath="${isodevice}/EFI/BOOT"
    fi
fi
configfile "${cmdpath}/grub.cfg"
EOF

    # Copy bootloader files
    cp /usr/lib/ISOLINUX/isolinux.bin "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/"
    cp /usr/lib/syslinux/modules/bios/* "$BUILDF/LIVE_BOOT/$DE/staging/isolinux/"
    cp -r /usr/lib/grub/x86_64-efi/* "$BUILDF/LIVE_BOOT/$DE/staging/boot/grub/x86_64-efi/"

    # Generate EFI bootable grub images
    grub-mkstandalone -O i386-efi --modules="part_gpt part_msdos fat iso9660" --locales="" --themes="" --fonts="" --output="$BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/BOOTIA32.EFI" "boot/grub/grub.cfg=$BUILDF/LIVE_BOOT/$DE/tmp/grub-embed.cfg"
    grub-mkstandalone -O x86_64-efi --modules="part_gpt part_msdos fat iso9660" --locales="" --themes="" --fonts="" --output="$BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/BOOTx64.EFI" "boot/grub/grub.cfg=$BUILDF/LIVE_BOOT/$DE/tmp/grub-embed.cfg"

    # Create UEFI boot disk image
    cd $BUILDF/LIVE_BOOT/$DE/staging && dd if=/dev/zero of=efiboot.img bs=1M count=20 && mkfs.vfat efiboot.img && mmd -i efiboot.img ::/EFI ::/EFI/BOOT && mcopy -vi efiboot.img $BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/BOOTIA32.EFI $BUILDF/LIVE_BOOT/$DE/staging/EFI/BOOT/BOOTx64.EFI $BUILDF/LIVE_BOOT/$DE/staging/boot/grub/grub.cfg ::/EFI/BOOT/

    # Copy kernel symlinks
    cp $BUILDF/LIVE_BOOT/$DE/chroot/boot/vmlinuz* $BUILDF/LIVE_BOOT/$DE/staging/live
    cp $BUILDF/LIVE_BOOT/$DE/chroot/boot/vmlinuz* $BUILDF/LIVE_BOOT/$DE/staging/boot

    # Generate the bootable iso disc image
    xorriso -as mkisofs -iso-level 3 -o "$BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.iso" -full-iso9660-filenames -volid "DEB13-LIVE" --mbr-force-bootable -partition_offset 16 -joliet -joliet-long -rational-rock -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -eltorito-boot isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table --eltorito-catalog isolinux/isolinux.cat -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot -isohybrid-gpt-basdat -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B $BUILDF/LIVE_BOOT/$DE/staging/efiboot.img "$BUILDF/LIVE_BOOT/$DE/staging"

    # Generate SHA256 hash of bootable iso
    echo -e "\n${BLUE}Generating iso hash, please wait.....${NC}"
    sha256sum $BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.iso > $BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.sha256sum

    # Set permissions on iso & hash
    chmod 777 $BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.iso
    chmod 777 $BUILDF/LIVE_BOOT/$DE/debian13-$DE-x64-livecd.sha256sum

    echo -e "\n${CYAN}${DE} live iso build completed in $BUILDF/LIVE_BOOT/$DE/${NC}\n"
    exit 1
}


######################################
# Desktop environment selection call #
######################################
env_select


###############################
# Build update selection call #
###############################
if [[ -d $BUILDF/LIVE_BOOT/$DE ]]; then
    echo -e "\n${YELLOW}Existing live CD build folder found.${NC} Please select:\n"
    PS3="Option: "
    select CHOICE1 in "Rebuild live CD iso" "Delete target build folder" "Chroot into target build" "Exit"; do
        if [[ "$CHOICE1" == "Exit" ]]; then
            echo -e "\n${CYAN}Script will exit.${NC}\n"
            exit 1
        elif [[ $CHOICE1 == "Delete target build folder" ]]; then
            echo -e "\n${RED}Warning:${NC} $DE and all associated build folders & files will be permanently deleted."
            read -p "Are you sure? [y/n] " DEL_RESPONSE1
                if [[ "${DEL_RESPONSE1,,}" == "n" ]]; then
                    echo -e "\n${BLUE}Deletion cancelled.${NC}\n"
                elif [[ "${DEL_RESPONSE1,,}" == "y" ]]; then
                    unmount_vfs # Unmount virtual filesystems if mounted
                    echo -e "\n${RED}$DE folder deleting...${NC}"
                    rm -rf $BUILDF/LIVE_BOOT/$DE
                    echo -e "\n${CYAN}$DE${NC} ${GREEN}build folder deleted. Script will exit.${NC}\n"
                    exit 1
                else
                    echo "Invalid selection. Please choose a number from the list."
                fi
        elif [[ $CHOICE1 == "Rebuild live CD iso" ]]; then
            echo -e "\n${CYAN}$DE${NC} live CD iso will be recreated from existing build....\n"
            echo -e "${BLUE}Rebuilding iso...${NC}"
	        unmount_vfs # Unmount virtual filesystems
            build_iso # Rebuild iso
        elif [[ $CHOICE1 == "Chroot into target build" ]]; then
            chroot_access # Interactive chroot session
        else
            echo "Invalid selection. Please choose a number from the list."
        fi
    done
fi


#####################################
# Pre-seed username & password loop #
#####################################
preseed_user_pass


########################
# Initialize workspace #
########################
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


################################
# Chroot into live environment #
################################
chroot $BUILDF/LIVE_BOOT/$DE/chroot /bin/bash << EOT
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

    apt update # Update package repositories

    # Essential programs
    apt install linux-image-amd64 live-boot systemd-sysv -y


    #################################
    # CLI (no gui, no xorg, no x11) #
    #################################
setup_cli() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install network-manager sudo nano gnupg zip unzip rar locales firmware-amd-graphics firmware-atheros amd64-microcode firmware-iwlwifi firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode wget exfat-fuse ntfs-3g lvm2 dosfstools mtools duf curl eza htop lm-sensors toilet figlet ssh sshfs parted screen rsync ufw git cryptsetup command-not-found -y

    # Add your custom packages here
    # apt install fail2ban aria2 ... -y

    # Command line docx viewer
    #cd /tmp
    #curl -L https://github.com/bgreenwell/doxx/releases/latest/download/doxx-$(uname -s)-$(uname -m).tar.gz | tar xz
    #chmod +x doxx && mv doxx /usr/local/bin/

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
}

    ######################
    # KDE Plasma desktop #
    ######################
setup_kde() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install kde-plasma-desktop plasma-nm sddm sddm-theme-breeze kwin-addons dolphin konsole sudo nano git pipx gnupg dmsetup zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools ufw pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs ssh sshfs screen rsync qtqr ufw git cryptsetup -y

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
}

    ################
    # MATE desktop #
    ################
setup_mate() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install mate-desktop-environment-core lightdm mate-media pulseaudio pulseaudio-utils alsa-utils network-manager-gnome mate-power-manager upower acpid sudo nano git pipx gnupg dmsetup unrar rar zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools ufw pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs keepassxc xclip mousepad ssh sshfs screen rsync qtqr ufw git cryptsetup -y

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
}

    ################
    # XFCE desktop #
    ################
setup_xfce() {
    # Core packages
    DEBIAN_FRONTEND=noninteractive apt install xfce4 xfce4-goodies lightdm network-manager-gnome sudo nano git pipx gnupg ssh dmsetup unrar rar zip unzip firmware-amd-graphics firmware-ath9k-htc firmware-iwlwifi firmware-realtek firmware-misc-nonfree firmware-brcm80211 firmware-b43-installer intel-microcode locales wget exfat-fuse ntfs-3g cryptsetup dosfstools mtools ufw pwgen duf curl eza htop lm-sensors toilet figlet gocryptfs cryfs keepassxc xclip ssh sshfs screen rsync qtqr ufw git cryptsetup -y

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
}


    #################################
    # Username & password functions #
    #################################
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
    "MATE")
        setup_mate
        ;;
    "XFCE")
        setup_xfce
        ;;
    esac

    # Call password functions
    def_user_pass
    hashed_pass

    # Housekeeping
    locale-gen en_US.UTF-8 # Set locale if unset
    rm -rf /tmp/* 2>/dev/null # Clear tmp dir

    # Fix for /dev/null errors
    rm -f /dev/null
    mknod -m 666 /dev/null c 1 3

    # Customize .bashrc to your preferences below
    cat << 'EOF' >> /home/${USER1}/.bashrc

#################################

# Colour variables
GREEN='\033[0;32m'
RED='\033[0;31m'
WHITE='\033[0;37m'
RESET='\033[0m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
LIGHTGRAY='\033[0;37m'

# Welcome message in ascii art
echo && echo && toilet -f smblock -w 80 -F metal "\$USER live" # Customize bashrc greeting here
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
export LESS_TERMCAP_mb=\$'\e[1;32m'
export LESS_TERMCAP_md=\$'\e[0;32m'
export LESS_TERMCAP_me=\$'\e[0m'
export LESS_TERMCAP_se=\$'\e[0m'
export LESS_TERMCAP_so=\$'\e[0;33m'
export LESS_TERMCAP_ue=\$'\e[0m'
export LESS_TERMCAP_us=\$'\e[0;4;37m'

###########################
# nnn file manager config #
###########################
# See homepage for keybindings & other custom settings: https://github.com/jarun/nnn/
# Plugin variables
export VISUAL=nano

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
EOF

    # Uncomment to customize .bash_aliases to your preferences below
    cat << 'EOF' > /home/${USER1}/.bash_aliases
# My aliases
alias bash_aliases='nano ~/.bash_aliases'
alias bashrc='nano ~/.bashrc'
alias l='eza --icons -a'
alias lsl='eza --tree --icons --level=2 -la'
alias duf='duf --hide-mp /var/log,/var/log.hdd,/run/lock,/run/user/1000'
alias rsync='rsync -r -a --stats --info=progress2'
EOF

    # Set correct permissions
    chmod 644 /home/${USER1}/.bash_aliases
    chown ${USER1}:${USER1} /home/${USER1}/.bash_aliases

    apt autoclean -y && apt autoremove -y # Clean up packages
    echo > /root/.bash_history # Delete root bash history

    echo $$
EOT


####################################################
# Clear sensitive variables after chroot completes #
####################################################
unset PASS1 USER1 CHRUSER1


########################
# Building live CD iso #
########################
unmount_vfs
build_iso
exit 1
