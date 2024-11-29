{
  inputs = {
    nixpkgs.url = "github:akechishiro/nixpkgs/debian-1208";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } ({ lib, ... }: {
    systems = [ "x86_64-linux" ];
    perSystem = { pkgs, ... }: {
      packages = lib.mapAttrs' (name: type: {
        name = lib.replaceStrings [".nix"] [""] name;
        value = pkgs.callPackage ./examples/${name} {};
      }) (builtins.readDir ./examples);
    };
  });
}
