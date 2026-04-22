# Debian 13 MATE Live CD/USB bootable OS build script
Version 2.20

April 2026


# RATIONALE
This script creates a bootable ISO image of Debian 13 desktop which can be burned to a CD or booted from a USB.

It's designed for secure work in an isolated environment, such as examining malicious code or crypto-currency managment offline. However this script was NOT designed to create an OS for anonymous web-browsing, masking IP locations, deep-web use etc. That is out of scope so I'd recommend using a different OS (hint: use Tails instead).

This Live CD/USB bootable OS runs completely from RAM. So files created during a session will not be saved and irreversibly deleted unless moved to a seperate disk. The purpose of this script is for you to build your own custom Live CD/USB bootable OS so you don't have to trust anybody else. You built it so you know what's in it.

To reduce proprietary code risk (hidden nasties), I tried to keep non-opensource software to a bare minimum. Unfortunately, building a completely opensource Live CD/USB OS means you probably won't get access to hardware such as wifi, bluetooth, sound, webcam, graphics cards etc so I believe this is the best compromise between useability and security. Debian 13 was chosen for it's rock-solid stability, genuine commitment to opensource philosophy, and no corporate backing (potential backdoors). Ubuntu and it's derivatives (yes, that includes Mint) cannot be trusted.

# Desktop environments available during build process:
- CLI (no GUI)
- KDE Plasma
- Mate
- XFCE

# CUSTOMIZATION
After building the iso you have the option to make changes to the filesystem in chroot. Then rebuild again to update the ISO. Please note that you cannot build a multi-user system. If you attempt to do so, you will create a broken franken-build. This Live CD / USB build was designed for a single user only.

The packages installed for each desktop environment were chosen for the best balance in lightweight resource use, convenience, and/or attractive graphical user interface. Sensible defaults are in place but can be easily changed by editing the bash script yourself. Liberal amount of comments have been added to the script so the purpose of each command can be understood clearly. You are welcome to modify the script, and add or delete packages as you wish.

If you wish to do so, you can further harden your custom build. See here for more details: https://www.debian.org/doc/manuals/securing-debian-manual/index.en.html


# SYSTEM REQUIREMENTS
There are no hard and fast rules regarding hardware requirements but I would suggest using at least a modern computer in the last 15 years:

- CPU - 1.5 GHz
- RAM - 2 GB

Anything less will make the user experience a real struggle. I would recommend at least 4 GB of RAM (ideally 16 GB) especially if you are going to download files. The exception is if you install the CLI environment. Baseline CLI environment RAM useage on a fresh boot is about 250 MB so you run it on a 1 GB system, which is ideal for remote or headless servers.

Also note that the build script can only be built from either Debian or Ubuntu-based linux desktop environments. Other linux derivatives such as Arch or Slackware are not supported and build will probably fail.

# INSTALLATION
To install, make executable and run script:

chmod +x "livecd-build-script-multi-desktop-github-2.20.sh"

sudo ./"livecd-build-script-multi-desktop-github-2.20.sh"


Build ISO is saved to your home directory ($HOME/LIVE_BOOT). SHA256 hash is generated if you want to distribute and check authenticity.

Burn to CD/DVD/USB and boot on your machine. UFEI and legacy BIOS are supported.

# DEFAULT SETTINGS
- LANGUAGE: US English
- LOCALE: en-US
- ROOT: disabled
- USER: (initalized by user). Sudo enabled.

# INSTALLED SOFTWARE
List of packages included in the Live CD/USB build. Note different desktop environments will have different package combinations:

- nano (terminal text editor)
- keepassxc (password manager & password generator)
- gnupg (terminal encryption, key management, identity validation)
- vlc (media player)
- brave (web browser)
- librewolf (hardened web browser)
- falkon (lightweight web browser)
- qtqr (QR code reader and generator)
- wget (terminal download manager)
- ufw (terminal firewall)
- parted (disk partition manager)
- screen (terminal multiplexer)
- rsync (remote file transfer & backup)
- toilet (terminal graphics print)
- figlet (terminal graphic print)
- zip (archiver)
- rar (archiver)
- htop (terminal system monitor)
- curl (terminal http transfer)
- wget (terminal web downloader)
- eza (enhanced ls)
- ssh (secure shell)
- sshfs (terminal remote filesystem mounter via secure shell)
- gocryptfs (terminal fuse-based file/folder encryption)
- cryfs (terminal fuse-based file/folder encryption)
- cryptsetup (terminal LUKS2 encryption suite)
- pwgen (terminal password generator)
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
Please review the Debian 13 LiveCD/USB bootable OS build script carefully. NEVER run a script blindly without understanding what it could do. Don't trust me. Google around to find out more. Research, research, research.

# LEGAL
Please note I am not responsible or liable for any damages or losses arising from your use or inability to use the script and or software used under this script. You are responsible for your use of this script. If you harm someone or get into a dispute with someone else, I will not be involved.
