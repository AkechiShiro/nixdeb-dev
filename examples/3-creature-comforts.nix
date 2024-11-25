{ lib, vmTools, systemd, gptfdisk, util-linux, dosfstools, e2fsprogs }:
vmTools.makeImageFromDebDist {
  inherit (vmTools.debDistros.debian12x86_64) name fullName urlPrefix packagesList;

  packages = lib.filter (p: !lib.elem p [
    "g++" "make" "dpkg-dev" "pkg-config"
    "sysvinit"
  ]) vmTools.debDistros.debian12x86_64.packages ++ [
    "systemd" # init system
    "init-system-helpers" # satisfy undeclared dependency on update-rc.d in udev hooks
    "systemd-sysv" # provides systemd as /sbin/init
    "linux-image-amd64" # kernel
    "initramfs-tools" # hooks for generating an initramfs
    "e2fsprogs" # initramfs wants fsck
    "grub-efi" # boot loader

    "apt" # package manager
    "ncurses-base" # terminfo to let applications talk to terminals better
    "openssh-server" # Remote login
    "dbus" # networkctl
  ];

  size = 8192;

  createRootFS = ''
    disk=/dev/vda
    ${gptfdisk}/bin/sgdisk $disk \
      -n1:0:+100M -t1:ef00 -c1:esp \
      -n2:0:0 -t2:8300 -c2:root

    ${util-linux}/bin/partx -u "$disk"
    ${dosfstools}/bin/mkfs.vfat -F32 -n ESP "$disk"1
    part="$disk"2
    ${e2fsprogs}/bin/mkfs.ext4 "$part" -L root
    mkdir /mnt
    ${util-linux}/bin/mount -t ext4 "$part" /mnt
    mkdir -p /mnt/{proc,dev,sys,boot/efi}
    ${util-linux}/bin/mount -t vfat "$disk"1 /mnt/boot/efi
    touch /mnt/.debug
  '';

  postInstall = ''
    # update-grub needs systemd to detect the filesystem UUID -- without,
    # we'll get root=/dev/vda2 on the cmdline which will only work in
    # a limited set of scenarios.
    ${systemd}/lib/systemd/systemd-udevd &
    ${systemd}/bin/udevadm trigger
    ${systemd}/bin/udevadm settle

    ${util-linux}/bin/mount -t sysfs sysfs /mnt/sys

    chroot /mnt /bin/bash -exuo pipefail <<CHROOT
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin

    # update-initramfs needs to know where its root filesystem lives,
    # so that the initial userspace is capable of finding and mounting it.
    echo LABEL=root / ext4 defaults > /etc/fstab

    # actually generate an initramfs
    update-initramfs -k all -c

    # APT sources so we can update the system and install new packages
    cat > /etc/apt/sources.list <<SOURCES
    deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
    deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
    
    deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
    deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
    
    deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
    deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
    SOURCES

    # TODO: INSTALL Kali Linux stuff 
    #apt update
    #apt upgrade -y
    #apt -y install wget gnupg dirmngr
    #wget -q -O - https://archive.kali.org/archive-key.asc | gpg --import
    #gpg --keyserver keyserver.ubuntu.com --recv-key 44C6513A8E4FB3D30875F758ED444FF07D8D0BF6
    #sh -c "echo 'deb http://http.kali.org/kali kali-rolling main non-free contrib' >> /etc/apt/sources.list"
    #sh -c "echo 'deb http://http.kali.org/kali kali-last-snapshot main non-free contrib' >> /etc/apt/sources.list"
    #gpg -a --export ED444FF07D8D0BF6 | sudo apt-key add -
    #apt update
    #apt -y upgrade
    #apt -y dist-upgrade
    #apt -y autoremove --purge
    #apt -y install kali-desktop-xfce xrdp kali-tools kali-linux


    # Install the boot loader to the EFI System Partition
    # Remove "quiet" from the command line so that we can see what's happening during boot
    cat >> /etc/default/grub <<EOF
    GRUB_TIMEOUT=5
    GRUB_CMDLINE_LINUX="console=ttyS0"
    GRUB_CMDLINE_LINUX_DEFAULT=""
    EOF
    sed -i '/TIMEOUT_HIDDEN/d' /etc/default/grub
    update-grub
    grub-install --target x86_64-efi

    # Configure networking using systemd-networkd
    ln -snf /lib/systemd/resolv.conf /etc/resolv.conf
    systemctl enable systemd-networkd systemd-resolved
    cat >/etc/systemd/network/10-eth.network <<NETWORK
    [Match]
    Name=en*
    Name=eth*

    [Link]
    RequiredForOnline=true

    [Network]
    DHCP=yes
    NETWORK

    # Remove SSH host keys -- the image shouldn't include
    # host-specific stuff like that, especially for authentication
    # purposes.
    rm /etc/ssh/ssh_host_*
    # But we do need SSH host keys, so generate them before sshd starts
    cat > /etc/systemd/system/generate-host-keys.service <<SERVICE
    [Install]
    WantedBy=ssh.service
    [Unit]
    Before=ssh.service
    [Service]
    ExecStart=dpkg-reconfigure openssh-server
    SERVICE
    systemctl enable generate-host-keys

    echo root:root | chpasswd
    # Prepopulate with my SSH key
    mkdir -p /root/.ssh
    chmod 0700 /root
    cat >/root/.ssh/authorized_keys <<KEYS
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILiE4hCgDRc4tGMICgq3KF9lNilZS55AEczleP0rwfUN akechi@guest
    KEYS
    CHROOT
    ${util-linux}/bin/umount /mnt/boot/efi
    ${util-linux}/bin/umount /mnt/sys
  '';
}
