# This list is based upon:
# https://github.com/TUM-DSE/doctor-cluster-config/blob/master/pkgs/xilinx/fhs-env.nix
pkgs:

let 
  myVim = (import ./my-nvim.nix {});
in
(with pkgs; [
  bash
  coreutils
  # fool buildFHSEnvChroot to think we are not on an FHS environment. See also:
  # https://unix.stackexchange.com/a/527763/135796
  (writeTextFile {
    name = "xilinx-fhs-etc_issue";
    # Upstream doesn't officially support NixOS (unfortunately), so it
    # doesn't matter really what we write here
    text = ''
      Welcome to NixOS (FHS environment for nix-xilinx)
    '';
    destination = "/etc/issue";
  })

  # Editor + kde deps
  alacritty
  # hack for cursor
  (runCommandLocal "breeze-cursors-fix" {} ''
    dir=$out/share/icons
    mkdir -p $dir
    ln -s ${kdePackages.breeze-icons}/share/icons/breeze_cursors $dir/default
  '')
  # hack to get editor working - need to run the following in another window:
  # nvim --listen ~/.cache/nvim/vivado_server.pipe
  (runCommandLocal "editor hack" {} ''
    mkdir -p $out/bin
    tgt=$out/bin/editor-hack
    echo "#!/usr/bin/env bash" >> $tgt
    echo 'nvim --server /home/gavin/.cache/nvim/vivado_server.pipe --headless --remote-send "<C-\\><C-N>:n $1<CR>"' >> $tgt
    chmod 111 $tgt
    '')

  zlib
  lsb-release
  stdenv.cc.cc
  ncurses5
  xorg.libXext
  xorg.libX11
  xorg.libXrender
  xorg.libXtst
  xorg.libXi
  xorg.libXft
  xorg.libxcb
  xorg.libxcb
  # common requirements
  freetype
  fontconfig
  glib
  # For string.h, see https://gitlab.com/doronbehar/nix-xilinx/-/issues/4
  glibc.dev
  gtk2
  gtk3
  libxcrypt-legacy
  # For fetching project templates when creating projects
  gitMinimal
  # For the `arch` command
  toybox

  # to compile some xilinx examples
  opencl-clhpp
  ocl-icd
  opencl-headers

  # from installLibs.sh
  graphviz
  # From some reason, without this lib.hiPrio, we don't get the crt1.o and
  # crti.o files needed by those who don't simulations.. See:
  # https://gitlab.com/doronbehar/nix-xilinx/-/issues/4
  (lib.hiPrio gcc)
  unzip
  nettools
])
