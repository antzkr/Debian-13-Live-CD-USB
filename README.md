# Debian 13 Live CD/USB build bash script
Version 3.01



# PURPOSE
This script creates a bootable ISO image of a Debian 13 OS which can be burned to a CD or booted from a USB. A 'one-click' solution for those who don't want to bother with complex configurations using the standard live build tools available, like lb build.

Just run this bash script, grab a coffee and come back in about 10 mins to a full ISO image ready to use.

The idea is for you to build (and customize) your own Live CD/USB bootable OS so you don't have to trust anybody else's distribution. You built it so you know what's in it.

# RATIONALE
This Live CD/USB bootable OS build is designed for secure work in an isolated environment, such as examining malicious code or crypto-currency managment offline. However this build was NOT designed to create an OS for anonymous web-browsing, masking IP locations, deep-web use etc. That is out of scope so I'd recommend using a different OS (hint: use Tails instead).

Two boot parameters are available in Grub/EFI:
- TORAM boot [USB can be removed]
- Normal boot [USB must remain attached]

TORAM boot loads the full filesystem into RAM. Normal boot marks the filesystem as read-only and writes changes to RAM. Both methods are secure. Files created during a live session will not be saved and will be irreversibly deleted, unless they are moved to a seperate disk. For systems with less than 8 GB, Normal boot is recommended otherwise runtime space will fill up very quickly. For systems with greater than 8 GB, TORAM is recommended for significant performance boost.

To reduce proprietary code risk (or other hidden nasties), I tried to keep non-opensource software to a bare minimum. Unfortunately, building a completely opensource Live CD/USB OS means you probably won't get access to hardware such as wifi, bluetooth, sound, webcam, graphics cards etc so I believe this build is the best compromise between useability and security. Debian 13 as a base was chosen for it's rock-solid stability, genuine commitment to opensource philosophy, huge package availability, and minimal corporate backing (potential backdoors). Ubuntu and it's derivatives (yes, that includes Mint) cannot be trusted.

# Desktop environments available during build process:
- CLI (no GUI)
- KDE Plasma
- Gnome
- Mate
- XFCE

# CUSTOMIZATION
After building the iso you have the option to make changes to the filesystem in chroot. Then rebuild again to update the ISO. Please note that you cannot build a multi-user system. If you attempt to do so, you will create a broken franken-build. This live build was designed for a single user only.

The packages installed for each desktop environment were chosen for the best balance in lightweight resource use, convenience, and/or attractive graphical user interface. Sensible defaults are in place but can be easily changed by editing the bash script yourself. Liberal amount of comments have been added to the script so the purpose of each command can be understood clearly. You are welcome to modify the script, and add or delete packages as you wish.

If you wish to do so, you can further harden your custom build. See here for more details: https://www.debian.org/doc/manuals/securing-debian-manual/index.en.html

# SYSTEM REQUIREMENTS
There are no hard and fast rules regarding hardware requirements but I would suggest using at least a modern computer in the last 15 years:

- CPU - 1.5 GHz
- RAM - 4 GB (Normal boot)
- RAM - 8 GB (TORAM boot)

Anything less will make the user experience a real struggle. The exception is if you install the CLI environment. Baseline CLI environment RAM useage on a fresh boot is about 250 MB so it's possible to run it on a 1+ GB system via Normal boot - achievable for remote or headless servers. Even so, the more RAM the better.

Also note that the build script can only be built from Debian-based linux desktop environments. Other linux derivatives such as Arch, Fedora or Slackware are not supported and build will probably fail.

# INSTALLATION
To install, make executable and run script on a debian-based linux system:

chmod +x livecd-build-script-multi-desktop-github-3.xx.sh

sudo ./livecd-build-script-multi-desktop-github-3.xx.sh


Build ISO is saved to your home directory ($HOME/LIVE_BOOT). SHA256 hash is generated if you want to distribute and check authenticity.

Burn to CD/DVD/USB and boot on your machine. UEFI and legacy BIOS are supported.

# DEFAULT SETTINGS
- LANGUAGE: US English
- LOCALE: en-US
- ROOT: disabled
- USERNAME: (initialized by user)
- PASSWORD: (initialized by user). Sudo enabled.

# INSTALLED SOFTWARE
List of packages included in the Live CD/USB build. Note different desktop environments will have different package combinations:

- nano (terminal text editor)
- keepassxc (password manager)
- gnupg (terminal encryption, key management, identity validation)
- vlc (media player)
- brave (feature-rich web browser)
- librewolf (hardened web browser)
- falkon (lightweight web browser)
- qtqr (QR code reader and generator)
- ufw (terminal firewall)
- parted (terminal disk partition manager)
- screen (terminal multiplexer)
- rsync (remote file transfer & backup)
- toilet (terminal graphics print)
- figlet (terminal graphics print)
- zip (compression archiver)
- rar (compression archiver)
- htop (terminal system monitor)
- curl (terminal http transfer)
- wget (terminal web downloader)
- eza (enhanced ls)
- ssh (secure shell)
- sshfs (terminal remote filesystem mount via secure shell)
- gocryptfs (terminal userspace encryption)
- cryfs (terminal hardened userspace encryption)
- cryptsetup (terminal LUKS2 encryption)
- pwgen (terminal secure password generator)
- nnn (terminal file manager)
- doxx (terminal docx viewer)
- pipx (python package manager)
- xclip (x11 clipboard)
- libreoffice-writer (office writer)
- libreoffice-calc (office spreadsheet)
- mousepad (text editor)

# List of firmware drivers included:
- firmware-ath9k-htc
- firmware-iwlwifi
- firmware-realtek
- firmware-misc-nonfree
- firmware-atheros
- firmware-brcm80211
- firmware-b43-installer
- amd64-microcode
- intel-microcode

# DISCLAIMER
Please review the Debian 13 LiveCD/USB bootable OS build script carefully. NEVER run a script blindly without understanding what it could do. Don't trust me. Google around to find out more. Please research, research, research.

# LEGAL
Please note that by downloading and running this script you acknowledge that I am not responsible or liable for any damages or losses arising from your use or inability to use the script and or software used under this script. You are solely responsible for your use of this script. If you harm someone or get into a dispute with a 3rd party, you consent to me waiving any involvement.
