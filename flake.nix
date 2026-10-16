{
  description = "Komplementary Kontrol - unofficial Linux support for the Komplete Kontrol A-series keyboards";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      # The two binaries plus the mapping/preset data files.
      # The Makefile discovers ALSA and hidapi through pkg-config, so the build
      # works with the Nix store layout (no /usr/include, no /usr/lib).
      mkKomplementaryKontrol =
        pkgs:
        pkgs.stdenv.mkDerivation (finalAttrs: {
          pname = "komplementary-kontrol";
          version = "0.1alpha8";

          src = lib.cleanSourceWith {
            src = ./.;
            filter =
              path: type:
              let
                base = baseNameOf path;
              in
              !(builtins.elem base [
                "obj"
                "result"
              ]);
          };

          nativeBuildInputs = [
            pkgs.pkg-config
            pkgs.gnumake
          ];
          buildInputs = [
            pkgs.alsa-lib
            pkgs.hidapi
          ];

          enableParallelBuilding = true;

          # MAPPINGS_PATH/PRESETS_PATH are compiled in, so they must point into
          # the store rather than /usr/share (which does not exist on NixOS).
          makeFlags = [
            "PREFIX=${placeholder "out"}"
          ];

          # Smoke test: both tools answer -h, and konfigure actually produces a
          # SysEx stream (0xf0 ... 0xf7) from the shipped preset. Both run
          # without touching the USB device.
          doCheck = true;
          checkPhase = ''
            runHook preCheck

            "./komplement" -h > komplement.usage
            grep -q "${finalAttrs.version}" komplement.usage
            echo "komplement -h: OK"

            "./konfigure" -h > konfigure.usage
            grep -q "${finalAttrs.version}" konfigure.usage || true
            echo "konfigure -h: OK"

            # -q keeps konfigure's verbose report off stdout so that only the
            # SysEx bytes are written.
            "./konfigure" -q -p presets/basic_cc.pst > sysex.syx
            test -s sysex.syx
            first_byte="$(od -An -tx1 -N1 sysex.syx | tr -d ' ')"
            test "$first_byte" = "f0"
            echo "konfigure -q -p presets/basic_cc.pst: OK ($(wc -c < sysex.syx) bytes of SysEx)"

            rm -f komplement.usage konfigure.usage sysex.syx

            # The -d dump logic, exercised with synthetic HID reports.
            "$CC" -Wall -Isrc -o hid_dump_test tests/hid_dump_test.c \
                  src/hid_dump.c src/button_names.c
            ./hid_dump_test
            rm -f hid_dump_test

            runHook postCheck
          '';

          meta = {
            description = "Utilities to make the Komplete Kontrol A-series keyboards usable under Linux";
            homepage = "https://github.com/fsphil/komplementary-kontrol";
            license = lib.licenses.gpl3Plus;
            mainProgram = "komplement";
            platforms = lib.platforms.linux;
          };
        });
    in
    {
      packages = forAllSystems (pkgs: rec {
        komplementary-kontrol = mkKomplementaryKontrol pkgs;
        default = komplementary-kontrol;
      });

      # `nix develop` -> gcc, make and pkg-config with ALSA + hidapi on the
      # PKG_CONFIG_PATH, so plain `make all` works on NixOS.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.gcc
            pkgs.gnumake
            pkgs.pkg-config
            pkgs.alsa-lib
            pkgs.alsa-utils
            pkgs.hidapi
            pkgs.usbutils
          ];

          shellHook = ''
            export PKG_CONFIG_PATH="${pkgs.alsa-lib.dev}/lib/pkgconfig:${pkgs.hidapi}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
            echo "komplementary-kontrol dev shell"
            echo "  pkg-config: $(pkg-config --modversion alsa) / $(pkg-config --modversion hidapi-libusb)"
            echo "  build: make all   install into the store: nix build"
          '';
        };
      });

      overlays.default = final: prev: {
        komplementary-kontrol = mkKomplementaryKontrol final;
      };

      # Optional NixOS module: installs the binaries, the udev rules for the
      # device and a rule that lets the `uinput` group write to /dev/uinput
      # (komplement needs that to synthesise key presses).
      nixosModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.services.komplementary-kontrol;
        in
        {
          options.services.komplementary-kontrol = {
            enable = lib.mkEnableOption "Komplementary Kontrol (Komplete Kontrol A-series support)";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              description = "The komplementary-kontrol package to install.";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = "audio";
              description = ''
                Group that gets read/write access to the keyboard and to
                /dev/uinput. Add your user to this group.
              '';
            };

            productIds = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "1730"
                "1740"
              ];
              example = [ "1740" ];
              description = ''
                USB product IDs (hex, lower case) of the Komplete Kontrol
                keyboards to grant access to: 1730 is the A25, 1740 the A49.
                Check your own keyboard with `lsusb | grep -i 17cc`.
              '';
            };

            installUdevRules = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Install the udev rules for the keyboard and /dev/uinput.";
            };

            loadUinputModule = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Load the uinput kernel module. Without it /dev/uinput does not
                exist at all, so the udev rule for it has nothing to apply to
                and komplement cannot send key presses.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];

            # /dev/uinput only exists once the module is loaded; without it the
            # rule below has nothing to apply to.
            boot.kernelModules = lib.mkIf cfg.loadUinputModule [ "uinput" ];

            services.udev.extraRules = lib.mkIf cfg.installUdevRules (
              lib.concatMapStrings (pid: ''
                # Komplete Kontrol A-series keyboard (17cc:${pid})
                SUBSYSTEM=="usb", ATTRS{idVendor}=="17cc", ATTRS{idProduct}=="${pid}", MODE="0660", GROUP="${cfg.group}"
                KERNEL=="hiddev*", ATTRS{idVendor}=="17cc", ATTRS{idProduct}=="${pid}", MODE="0660", GROUP="${cfg.group}"
              '') cfg.productIds
              + ''
                # uinput, used by komplement to send key presses
                KERNEL=="uinput", MODE="0660", GROUP="${cfg.group}", OPTIONS+="static_node=uinput"
              ''
            );

            users.groups.${cfg.group} = { };
          };
        };
    };
}
