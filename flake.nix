{
  description = "A flake for bash, coreutils, xxd, restic, util-linux, and openssh";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            coreutils
            kcov
            vim # provides xxd
            python3
            python312Packages.fusepy
            restic
            screen
            shellcheck
            tmux
            utillinux
            openssh
          ];
        };
      }
    );
}
