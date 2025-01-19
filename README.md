# Working code for building Debian bootable and Kali Linux image from Nix 

- See examples/4-kali-linux.nix
- See examples/3-creature-comforts for Debian

## How to use 

First of all, you will need to install `nix` : [follow the instructions in this repository](https://github.com/DeterminateSystems/nix-installer?tab=readme-ov-file#install-nix)

Clone the project : 
```
git clone https://github.com/AkechiShiro/nixdeb-dev -b debian12-vm-images
cd nixdeb-dev
```

Inside the root of the project for Debian VMs, you can do the following :
```
nix build -o ovmf nixpkgs#OVMF.fd
nix build -o image .#3-creature-comforts.nix
nix run nixpkgs#qemu_kvm -- \
  -m 4G -smp 4 \
  -bios ovmf-fd/FV/OVMF.fd \
  -snapshot \
  image/disk-image.qcow2
```
> [!NOTE]
>  All write operation to the disk will not be written to the disk but will be held in RAM due to the `-snapshot` qemu option.

For the Kali Linux VM : 
```
nix build -o ovmf nixpkgs#OVMF.fd
nix build -o image .#3-creature-comforts.nix
nix run nixpkgs#qemu_kvm -- \
  -m 4G -smp 4 \
  -bios ovmf-fd/FV/OVMF.fd \
  -snapshot \
  image/disk-image.qcow2
```


## Original

# Full working code for building bootable Ubuntu images from Nix

See [the accompanying blog post](https://linus.schreibt.jetzt/posts/ubuntu-images.html).
