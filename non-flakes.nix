{system ? builtins.currentSystem}: let
  pkgs = import <nixpkgs> {
    inherit system;
  };
in
  pkgs.stdenv.mkDerivation {
    name = "out";

    unpackPhase = "true";

    nativeBuildInputs = [
      pkgs.rustc
    ];

    buildPhase = ''
      echo 'fn main() { }' > main.rs
      rustc main.rs
    '';

    installPhase = ''
      cp main $out
    '';
  }
