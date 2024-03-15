{
  description = "Nix files made to ease imperative installation of Xilinx tools";

  # https://nixos.wiki/wiki/Flakes#Using_flakes_project_from_a_legacy_Nix
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };

  outputs = { self, nixpkgs, flake-compat }: 
  let
    # We don't use flake-utils.lib.eachDefaultSystem since only x86_64-linux is
    # supported
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    guiTargetPkgs = import ./common-gui-deps.nix;
    runScriptPrefix = { errorOut ? true, petalinux ? false }: let
      # The name of the environment variable that tells us where petalinux /
      # vitis & vivado are installed.
      INSTALL_DIR_VAR = if petalinux then
        # The choice of `PETALINUX` as the variable name is based on the same
        # variable used in the `settings.sh` file generated by the installer.
        # It may be that this environment variable is also used by the
        # petalinux binaries, so we don't 
        "PETALINUX"
      else
        # This naming OTH, is arbitrary.
        "INSTALL_DIR"
      ;
      # For the first script comment
      toolName = if petalinux then
        "petalinux"
      else
        "xilinx"
      ;
    in ''
      # Search for an imperative declaration of the installation directory of ${toolName}
      if [[ -f ~/.config/xilinx/nix.sh ]]; then
        source ~/.config/xilinx/nix.sh
    '' + pkgs.lib.optionalString errorOut (''
      else
        echo "nix-xilinx: error: Did not find ~/.config/xilinx/nix.sh" >&2
        exit 1
      fi
      if [[ ! -d "''${${INSTALL_DIR_VAR}}" ]]; then
        echo "nix-xilinx: error: ${INSTALL_DIR_VAR} "''${${INSTALL_DIR_VAR}}" isn't a directory" >&2
        exit 2
      else
        export ${INSTALL_DIR_VAR}
    '' + /*

        petalinux provides a settings.sh found in $PETALINUX directory. It is
        intended to be sourced whenever you want to want to use petalinux'
        tools - very bad design of course. Not only that, it seems buggy,
        according to my tests with version 2023.2. 

        The ideal design, which is implemented here is that every tool is
        standalone. Since we know from experience the installation directory's
        structure, we can set the environment variables set there by
        ourselves...

        */ pkgs.lib.optionalString petalinux ''
        # The only thing we get from settings.sh is the version string -
        # probably insignificant, but whatever...
        export PETALINUX_VER="$(grep 'export PETALINUX_VER=' "$PETALINUX/settings.sh" | head -1 | sed 's/^.*=//')"
        export PETALINUX_MAJOR_VER=''${PETALINUX_VER%%.*}
        export XSCT_TOOLCHAIN="$PETALINUX/tools/xsct"
        PATH="$XSCT_TOOLCHAIN/gnu/aarch32/lin/gcc-arm-none-eabi/bin:$PATH"
        PATH="$XSCT_TOOLCHAIN/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin:$PATH"
        PATH="$XSCT_TOOLCHAIN/gnu/aarch64/lin/aarch64-none/bin:$PATH"
        PATH="$XSCT_TOOLCHAIN/gnu/aarch64/lin/aarch64-linux/bin:$PATH"
        PATH="$XSCT_TOOLCHAIN/gnu/armr5/lin/gcc-arm-none-eabi/bin:$PATH"
        PATH="$XSCT_TOOLCHAIN/gnu/microblaze/lin/bin:$PATH"
        PATH="$PETALINUX/tools/xsct/petalinux/bin:$PETALINUX/tools/common/petalinux/bin:$PATH"
        "$PETALINUX/tools/common/petalinux/utils/petalinux-env-check"
    '') + ''
      fi
    '';
    # Used in many packages
    metaCommon = with pkgs.lib; {
      # This license is not of Xilinx' tools, but for this repository
      license = licenses.mit;
      # Probably best to install this completely imperatively on a system other
      # then NixOS.
      platforms = platforms.linux;
    };

    createXilinxPkg = {product, meta}: let
      name = pkgs.lib.strings.toLower product;
      desktopItem = pkgs.makeDesktopItem {
        desktopName = product;
        inherit name;
        exec = "@out@/bin/${name}";
        icon = name;
        categories = [
          "Utility"
          "Development"
          "IDE"
        ];
      };
      xdg_icon_cmd_prefix = "env XDG_DATA_HOME=$out/share ${pkgs.xdg-utils}/bin/xdg-icon-resource install --novendor --size $size --mode user";
    in pkgs.buildFHSEnvChroot {
      inherit name;
      targetPkgs = guiTargetPkgs;
      runScript = pkgs.writeScript "xilinx-${product}-runner" ((runScriptPrefix {}) + ''
        if [[ -d $INSTALL_DIR/${product}/$VERSION ]]; then
          $INSTALL_DIR/${product}/$VERSION/bin/${name} "$@"
        else
          echo It seems ${product} isn\'t installed because '$INSTALL_DIR/${product}/$VERSION' doesn\'t exist. Follow >&2
          echo the instructions in the README of nix-xilinx and make sure ${product} is selected during the >&2
          echo installation wizard. If it\'s supposed to be installed, check that your \~/.config/xilinx/nix.sh >&2
          echo have a correct '$VERSION' variable set in it - check that the '$VERSION' directory actually exists. >&2
          exit 1
        fi
      '');
      inherit meta;
      extraInstallCommands = ''
        install -Dm644 ${desktopItem}/share/applications/${name}.desktop $out/share/applications/${name}.desktop
        substituteInPlace $out/share/applications/${name}.desktop \
          --replace "@out@" ${placeholder "out"}
        for size in 64 256 512; do
          ${{
            vivado = "${xdg_icon_cmd_prefix} ${./icons/vivado.png} ${name}";
            vitis_hls = "${xdg_icon_cmd_prefix} ${./icons/vitis_hls.png} ${name}";
            vitis = "echo nix-xilinx warning: No icon is available for product ${product} >&2";
            model_composer = "${xdg_icon_cmd_prefix} ${./icons/matlab.png} ${name}";
          }.${name}}
        done
      '';
    };
    petalinuxTargetPkgs = p: let
      ncurses5' = p.ncurses5.overrideAttrs (old: {
        configureFlags = old.configureFlags ++ [ "--with-termlib" ];
        postFixup = "";
      });
      ncurses5'-unicode = ncurses5'.override { unicodeSupport = false; };
    in [
      p.autoconf
      p.automake
      p.gnumake
      p.libtool
      p.coreutils
      p.gcc
      p.bc
      p.zlib
      p.zlib.dev
      # https://github.com/NixOS/nixpkgs/issues/218534
      # postFixup would create symlinks for the non-unicode version but since it breaks
      # in buildFHSEnvChroot, we just install both variants
      ncurses5'
      ncurses5'.dev
      ncurses5'-unicode
      ncurses5'-unicode.dev
      p.stdenv.cc
      p.libxcrypt-legacy
      # 
      (p.libedit.override {
        ncurses = ncurses5'-unicode;
      })
    ];
    installShellMessage = toolStr: let
      asciidocInstructionsFile = if toolStr == "petalinux" then
        ./install-petalinux.adoc
      else
        ./install-gui-tools.adoc
      ;
    in ''
      cat <<EOF
      ============================
      welcome to nix-xilinx ${toolStr} installation shell!

      To install ${toolStr}:
      ${nixpkgs.lib.strings.escape ["`" "'" "\"" "$"] (builtins.readFile asciidocInstructionsFile)}

      Exit the shell with `exit`, and follow the rest of the instructions in the
      README to make the installed executables available anywhere on your
      system.
      ============================
      EOF
    '';
  in {
    packages.x86_64-linux.xilinx-shell = pkgs.buildFHSEnvChroot {
      name = "xilinx-shell";
      targetPkgs = guiTargetPkgs;
      runScript = pkgs.writeScript "xilinx-shell-runner" (
        (runScriptPrefix {
          # If the user hasn't setup a ~/.config/xilinx/nix.sh file yet, don't
          # yell at them that it's missing
          errorOut = false;
        }) + (installShellMessage "Vivado & Vitis") + ''
        exec bash
      '');
      meta = metaCommon // {
        homepage = "https://gitlab.com/doronbehar/nix-xilinx";
        description = "A bash shell from which you can install xilinx tools or launch them from CLI";
      };
    };
    packages.x86_64-linux.petalinux-install-shell = pkgs.buildFHSEnvChroot {
      name = "petalinux-install-shell";
      targetPkgs = petalinuxTargetPkgs;
      runScript = pkgs.writeScript "petalinux-install-shell-script" (
        (runScriptPrefix {
          petalinux = true;
          # If the user hasn't setup a ~/.config/xilinx/nix.sh file yet, don't
          # yell at them that it's missing
          errorOut = false;
        }) + (installShellMessage "petalinux") + ''
        exec bash
      '');
      meta = metaCommon // {
        homepage = "https://gitlab.com/doronbehar/nix-xilinx";
        description = "A bash shell from which you can install petalinux tools or launch them from CLI";
      };
    };
    packages.x86_64-linux.petalinux = pkgs.buildFHSEnvChroot {
      name = "petalinux";
      targetPkgs = petalinuxTargetPkgs;
      runScript = pkgs.writeShellScript "petalinux-wrapper" ((runScriptPrefix {
        petalinux = true;
      }) + ''
        exec "$PETALINUX/tools/common/petalinux/bin/petalinux-$NIX_PETALINUX_TOOL" "$@"
      '');
      extraInstallCommands = ''
        # Can't use nativeBuildInputs with buildFHSEnvChroot
        source ${pkgs.makeWrapper}/nix-support/setup-hook
      '' + pkgs.lib.pipe [
        "boot" "build" "config" "create" "devtool" "package" "upgrade" "util"
      ] [
        (map (t: ''
          makeWrapper $(readlink $out/bin/petalinux) $out/bin/petalinux-${t} \
            --set NIX_PETALINUX_TOOL ${t}
        ''))
        pkgs.lib.concatStrings
      ] + ''
        # This is here due to the `name` nix argument - not really needed after
        # we create the wrappers.
        rm $out/bin/petalinux
      '';
      meta = metaCommon // {
        homepage = "https://gitlab.com/doronbehar/nix-xilinx";
        description = "petalinux-* tools";
      };
    };
    packages.x86_64-linux.vivado = createXilinxPkg {
      product = "Vivado";
      meta = metaCommon // {
        homepage = "https://www.xilinx.com/products/design-tools/vivado.html";
        description = "Software suite for synthesis and analysis of (HDL) designs";
      };
    };
    packages.x86_64-linux.vitis = createXilinxPkg {
      product = "Vitis";
      meta = metaCommon // {
        homepage = "https://www.xilinx.com/products/design-tools/vitis.html";
        description = "A comprehensive development environment";
      };
    };
    packages.x86_64-linux.vitis_hls = createXilinxPkg {
      product = "Vitis_HLS";
      meta = metaCommon // {
        homepage = "https://xilinx.github.io/Vitis-Tutorials/2020-2/docs/Getting_Started/Vitis_HLS/README.html";
        description = "High-Level Synthesis from C, C++ and OpenCL";
      };
    };
    packages.x86_64-linux.model_composer = createXilinxPkg {
      product = "Model_Composer";
      meta = metaCommon // {
        homepage = "https://www.xilinx.com/products/design-tools/vitis/vitis-model-composer.html";
        description = "A Xilinx toolbox for MATLAB and Simulink for DSP Design";
      };
    };
    overlay = final: prev: {
      inherit (self.packages.x86_64-linux)
        xilinx-shell
        vivado
        vitis
        vitis_hls
        model_composer
        petalinux-install-shell
        petalinux
      ;
    };
    # Might be useful for usage of this flake in another flake with devShell +
    # direnv setup. See:
    # https://gitlab.com/doronbehar/nix-matlab/-/merge_requests/1#note_631741222
    shellHooksCommon = (runScriptPrefix {}) + ''
      # Rename the variables for others to extend it in their shellHook
      export XILINX_INSTALL_DIR="$INSTALL_DIR"
      unset INSTALL_DIR
      export XILINX_VERSION=$VERSION
      unset VERSION
    '';
    # If you want to do something a bit more custom
    inherit runScriptPrefix;
    devShell.x86_64-linux = pkgs.mkShell {
      buildInputs = (guiTargetPkgs pkgs) ++ [
        self.packages.x86_64-linux.xilinx-shell
      ];
      # From some reason using the attribute xilinx-shell directly as the
      # devShell doesn't make it run like that by default.
      shellHook = ''
        exec xilinx-shell
      '';
    };

    defaultPackage.x86_64-linux = self.packages.x86_64-linux.xilinx-shell;

  };
}
