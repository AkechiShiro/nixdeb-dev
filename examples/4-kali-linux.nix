{ lib, vmTools, systemd, gptfdisk, util-linux, dosfstools, e2fsprogs }:

let 
   # VM Disk Size in Gigabyte
   vmSize = 8192;
in
vmTools.makeImageFromDebDist {
  inherit (vmTools.debDistros.kalilinuxRollingx86_64) name fullName urlPrefix packagesList;

  packages = lib.filter (p: !lib.elem p [
    "g++" "make" "dpkg-dev" "pkg-config"
    "sysvinit"
  ]) vmTools.debDistros.kalilinuxRollingx86_64.packages ++ [
    "systemd" # init system
    "systemd-resolved" # needed for networkctl
    "dbus" # needed for networkctl

    "init-system-helpers" # satisfy undeclared dependency on update-rc.d in udev hooks
    "systemd-sysv" # provides systemd as /sbin/init
    "linux-image-amd64" # kernel
    "linux-headers-amd64" # kernel
    "initramfs-tools" # hooks for generating an initramfs
    "e2fsprogs" # initramfs wants fsck
    "grub-efi" # boot loader

    "apt" # package manager
    "ncurses-base" # terminfo to let applications talk to terminals better
    "openssh-server" # Remote login
    "zstd" # initramfs better compression than gzip
    "inetutils-tools" # ping/traceroute/ftp/telnet binaries

    # Custom packages I need
    "neovim"
    "lsd" # better ls
    "ncdu"
    "wget"
    "gnupg"
    "dirmngr"
    # Needed for xfce4 autostart
    "xinit"
    "xserver-xorg-core"
    "keyboard-configuration"
    "dialog"
    # Kali Meta packages
    "kali-desktop-xfce"
    "kali-desktop-core"
    "kali-linux-core"
  ];

  size = vmSize;

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
    echo "LABEL=root / ext4 defaults" > /etc/fstab
    echo "LABEL=ESP /boot/efi vfat defaults,umask=0077" >> /etc/fstab

    # actually generate an initramfs
    update-initramfs -k all -c

    # APT sources so we can update the system and install new packages
    cat > /etc/apt/sources.list <<SOURCES
    deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
    SOURCES

    # Install the boot loader to the EFI System Partition
    # Remove "quiet" from the command line so that we can see what's happening during boot
    cat >> /etc/default/grub <<EOF
    GRUB_TIMEOUT=5
    GRUB_CMDLINE_LINUX="console=ttyS0"
    GRUB_CMDLINE_LINUX_DEFAULT=""
    EOF
    sed -i '/TIMEOUT_HIDDEN/d' /etc/default/grub
    update-grub
    grub-install --target x86_64-efi --removable

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
    systemctl enable ssh

    echo root:root | chpasswd
    # Prepopulate with my SSH key
    mkdir -p /root/.ssh
    chmod 0700 /root
    cat >/root/.ssh/authorized_keys <<KEYS
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILiE4hCgDRc4tGMICgq3KF9lNilZS55AEczleP0rwfUN akechi@guestIntel
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDWlTEs5InoyFHmUJipTZsgeYK9zbFWlcR5fxsWb3pB7 akechi@guestAMD
    KEYS
    CHROOT
    ${util-linux}/bin/umount /mnt/boot/efi
    ${util-linux}/bin/umount /mnt/sys
  '';
}
