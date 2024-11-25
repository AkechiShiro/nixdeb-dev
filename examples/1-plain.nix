{ vmTools, ... }:
let distro = vmTools.debDistros.debian12x86_64; in
vmTools.makeImageFromDebDist {
  inherit (distro) name fullName urlPrefix packagesList;
  packages = distro.packages ++ ["systemd" "zsh" "vim"];
}
