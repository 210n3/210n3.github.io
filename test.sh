sed -i 's/HOOKS=(base\ udev\ autodetect\ modconf\ block\ filesystems\ keyboard\ fsck)/HOOKS="base\ udev\ autodetect\ modconf\ block\ encrypt\ filesystems\ keyboard\ fsck"/' /etc/mkinitcpio.conf
