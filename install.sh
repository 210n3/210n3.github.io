echo "working"
parted --script /dev/$DISK \
        mklabel gpt \
        mkpart ESP fat32 1MiB 200MiB \
        set 1 boot on \
        name 1 efi \
        mkpart primary 200MiB 800MiB \
        name 2 boot \
        mkpart primary 800MiB 32Gib \
        name 3 swap \
        mkpart primary 32GiB 100% \
        name 3 btrfs \
        print \
        quit
