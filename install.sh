#!/bin/bash

DEBUG=false # set to true to debug
# setfont ter-132n

function pause() {
    if $DEBUG; then
        read -p "$*"        
    fi
}

function base() {
    # this is a hack
    P1="1"
    P2="2"

    # get disk name
    cat /proc/partitions
    read -p "Enter the device name ... " READ

    DISK=$READ

    # overwrite it with random data
    pause 'Wiping Disk [Enter]'
    badblocks -c 10240 -s -w -t random -v /dev/$DISK

    pause 'Create Partitions [Enter]'
    parted --script /dev/$DISK \
        mklabel gpt \
        mkpart ESP fat32 1MiB 300MiB \
        set 1 boot on \
        name 1 efi \
        mkpart primary 300MiB 100% \
        name 2 btrfs \
        print \
        quit


    # create LUKS volume
    pause 'Create LUKS volume [Enter]'
    cryptsetup luksFormat /dev/$DISK$P2

    # open the root luks volume
    pause 'Open LUKS volume [Enter]'
    cryptsetup luksOpen /dev/$DISK$P2 encroot

    # format Partitions
    pause 'Format Partitions [Enter]'
    mkfs.fat -F32 /dev/$DISK$P1
    mkfs.btrfs /dev/mapper/encroot

    # mount the root filesystem
    pause 'Mount root filesystem [Enter]'
    mount /dev/mapper/encroot /mnt

    # create the subvolumes
    pause 'Create subvolumes [Enter]'
    cd /mnt
    btrfs su cr @
    btrfs su cr @home
    btrfs su cr @snapshots
    btrfs su cr @var_log    
    cd 
    umount /mnt

    # mount the subvolumes
    pause 'Mount subvolumes [Enter]'
    mount -o noatime,compress=lzo,space_cache,subvol=@ /dev/mapper/encroot /mnt
    mkdir -p /mnt/{boot,home,.snapshots,var/log}
    mount -o noatime,compress=lzo,space_cache,subvol=@home /dev/mapper/encroot /mnt/home
    mount -o noatime,compress=lzo,space_cache,subvol=@snapshots /dev/mapper/encroot /mnt/.snapshots
    mount -o noatime,compress=lzo,space_cache,subvol=@var_log /dev/mapper/encroot /mnt/var/log

    sync

    # mount other partitions
    pause 'Mount boot partitions [Enter]'
    mount /dev/$DISK$P1 /mnt/boot

    # install Arch Linux
    pause 'Pacstrap [Enter]'
    pacstrap /mnt base linux linux-firmware vim intel-ucode --noconfirm

    # generate /etc/fstab
    pause 'Generate /etc/fstab [Enter]'
    genfstab -p -U /mnt >> /mnt/etc/fstab


    # copy script to /mnt ready to be run after chroot
    cp archinstall.sh /mnt/root/

    # chroot
    pause 'About to chroot after which script will terminate. Please re-run script for phase2 [Enter]'
    arch-chroot /mnt
}

function config() {
    # set the timezone & hardware clock
    pause 'Set the timezone & hardware clock [Enter]'
    ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
    hwclock --systohc --utc

    # Generate the required locales
    pause 'Generated the required locales [Enter]'
    cp /etc/locale.gen /etc/local.gen.bak
    echo "en_IN.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_IN.UTF-8" > /etc/locale.conf


    # hostname
    pause 'Hostname & Hosts [Enter]'
    read -p "Enter your hostname : " MYHOST
    echo $MYHOST > /etc/hostname
    echo "127.0.0.1	localhost"                       >> /etc/hosts
    echo "::1		localhost"                       >> /etc/hosts
    echo "127.0.1.1	iamgroot.localdomain	$MYHOST" >> /etc/hosts
    cat /etc/hosts

    # set the root password
    echo 'Enter a new root password.'
    passwd root

    #packages minimal
    pacman -S grub efibootmgr networkmanager network-manager-applet dialog wpa_supplicant mtools dosfstools git reflector snapper bluez bluez-utils cups hplip xdg-utils xdg-user-dirs alsa-utils pulseaudio pulseaudio-bluetooth  base-devel linux-headers terminus-font acpi xf86-input-libinput libinput

    # mkinitcpio
    pause 'mkinitcpio, modify hooks [Enter]'
    cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
    sed -i 's/MODULES()/MODULES=(btrfs)' /etc/mkinitcpio.conf
    sed -i 's/HOOKS=(base\ udev\ autodetect\ modconf\ block\ filesystems\ keyboard\ fsck)/HOOKS="base\ udev\ autodetect\ modconf\ block\ encrypt\ filesystems\ keyboard\ fsck"/' /etc/mkinitcpio.conf
    mkinitcpio -p linux

    # install grub
    pause 'install grub [Enter]'
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable --recheck 

    # configure grub to support LUKS kernel parameters
    pause 'configure grub to support LUKS kernel parameters [Enter]'
    cp /etc/default/grub /etc/default/grub.bak
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="cryptdevice=\/dev\/sda3:encroot\ root=\/dev\/mapper\/encroot\ rootflags=subvol=__active\/rootvol\ quiet"/' /etc/default/grub

    # generate grub.cfg file:
    grub-mkconfig -o /boot/grub/grub.cfg

    # autostart network manager & sshd
    systemctl enable NetworkManager
    systemctl enable sshd
    systemctl enable cups
    systemctl enable bluetooth

    # Create User Account
    pause 'Create user account [Enter]'
    read -p "Enter your username: " USERNAME
    useradd -m -G wheel $USERNAME
    passwd $USERNAME


    # Allow wheel users to SUDO
    pause 'Allow wheel users to SUDO [Enter]'
    echo "%wheel ALL=(ALL) ALL" | (EDITOR="tee -a" visudo)


    # copy script to user folder ready for phase3
    cp archinstall.sh /home/$USERNAME

    # exit and reboot
    echo 'About to exit script. Time to reboot and login as a user.'
    echo 'Type exit [Enter] to exit CHROOT.'
    echo 'Type reboot [Enter] to reboot.'
    echo 'After rebooting ssh %USERNAME@<IP ADDRESS>.'
    echo 'Remember - You will need to enter your LUKS password at the console to boot.'
    pause 'Press [Enter]'
    sync

}

# //----------------------------------------------------------------------------
# // Function : phase3()
# //----------------------------------------------------------------------------
# // Purpose  : This phase runs in the end user account, on first boot
# //----------------------------------------------------------------------------
function setup() {
    sudo umount /.snapshots
    sudo rm -r /.snapshots
    sudo snapper -c root create-config /
    sudo btrfs su del /.snapshots
    sudo mkdir /.snapshots
    sudo mount -a
    sudo chmod 750 /.snapshots
    read -p "Enter your username: " USERNAME
    sed -i "s/ALLOW_USER=""/ALLOW_USERS="$USERNAME"" /etc/snapper/config/root
    sed -i 's/TIMELINE_MIN_AGE="1000"/TIMELINE_MIN_AGE="1000"       ' /etc/snapper/config/root
    sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="5"  ' /etc/snapper/config/root
    sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="7"    ' /etc/snapper/config/root
    sed -i 's/TIMELINE_LIMIT_WEEKLY="0"/TIMELINE_LIMIT_WEEKLY="0"   ' /etc/snapper/config/root
    sed -i 's/TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="0"' /etc/snapper/config/root
    sed -i 's/TIMELINE_LIMIT_YEARLY="10"/TIMELINE_LIMIT_YEARLY="0"  ' /etc/snapper/config/root

    sudo systemctl enable --now snapper-timeline.timer
    sudo systemctl enable --now snapper-cleanup.timer

    git clone https://aur.archlinux.org/yay.git
    cd yay/
    makepkg -si PKGBUILD --noconfirm
    cd ..
    sudo rm -dR yay/

    yay -S snap-pac-grub snapper-gui
    sudo pacman -S arc-gtk-theme arc-icon-theme xf86-video-intel xorg-server xorg-xinit chromium rsync qtile python-pip alacritty zsh 
    sudo mkdir /etc/pacman.d/hooks
    echo "[Trigger]                                            " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "Operation = Upgrade                                  " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "Operation = Install                                  " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "Operation = Remove                                   " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "Type = Path                                          " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "Target = boot/*                                      " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "                                                     " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "[Action]                                             " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "Depends = rsync                                      " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "Description = Backing up /boot...                    " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "When = PreTransaction                                " >> /etc/pacman.d/hooks/50-bootbackup.hook
    echo "Exec = /usr/bin/rsync -a --delete /boot /.bootbackup " >> /etc/pacman.d/hooks/50-bootbackup.hook
    sudo chmod a+rx /.snapshots
    sudo chown :$USERNAME /.snapshots
}



# ask for phase number 
echo -e "1)base\n2)config\n3)setup"
read -p "Enter phase number (1-3) : " NO

# select script
if [ "$NO" == "1" ]; then
    base
elif [ "$NO" == "2" ]; then
    config
elif [ "$NO" == "3" ]; then
    setup
else
    echo "Error: Incorrect number"
fi
