{
  lib,
  writeShellApplication,
  writeShellScriptBin,
  callPackage,
  apple-sdk_26,
  zig_0_15,
  gettext,
  ncurses,
  pandoc,
  pkg-config,
  rsync,
  stdenv,
  revision ? "dirty",
}: let
  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.intersection (lib.fileset.fromSource (lib.sources.cleanSource ../.)) (
      lib.fileset.unions [
        ../dist
        ../images
        ../include
        ../macos
        ../po
        ../pkg
        ../src
        ../vendor
        ../build.zig
        ../build.zig.zon
      ]
    );
  };
  deps = callPackage ../build.zig.zon.nix {};
  xcrun = writeShellScriptBin "xcrun" ''
    case "$*" in
      "--sdk macosx --show-sdk-path"|"-sdk macosx --show-sdk-path"|"--show-sdk-path")
        echo ${lib.escapeShellArg (toString apple-sdk_26.sdkroot)}
        ;;
      *)
        exec /usr/bin/xcrun "$@"
        ;;
    esac
  '';
  arch =
    if stdenv.hostPlatform.isAarch64
    then "arm64"
    else "x86_64";
in
  writeShellApplication {
    name = "build-ghostty-macos";
    runtimeInputs = [gettext ncurses pandoc pkg-config rsync];
    text = ''
      if [[ "''${1:-}" == "--help" ]]; then
        echo "Usage: build-ghostty-macos [output-directory]"
        echo "Builds the flake's Ghostty source with local Xcode into output-directory/Ghostty.app."
        echo "The default output directory is ./zig-out. Run as your normal user."
        exit 0
      fi
      if (( $# > 1 )) || [[ "''${1:-}" == -* ]]; then
        echo "Usage: build-ghostty-macos [output-directory]" >&2
        exit 1
      fi
      if (( EUID == 0 )); then
        echo "Run this build as your normal user, without sudo." >&2
        exit 1
      fi

      export DEVELOPER_DIR="''${DEVELOPER_DIR:-$(/usr/bin/xcode-select --print-path)}"
      if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
        echo "Select a full Xcode installation with xcode-select, or set DEVELOPER_DIR." >&2
        exit 1
      fi
      unset SDKROOT
      if ! /usr/bin/xcrun --sdk macosx metal --version; then
        echo "Install the Metal Toolchain in Xcode Settings > Components, then retry." >&2
        exit 1
      fi

      output_dir="''${1:-$PWD/zig-out}"
      /bin/mkdir -p "$output_dir"
      output_dir="$(cd "$output_dir" && pwd -P)"
      build_dir="$(/usr/bin/mktemp -d "''${TMPDIR:-/tmp}/ghostty-build.XXXXXX")"
      trap '/bin/rm -rf "$build_dir"' EXIT
      /bin/cp -R ${source}/. "$build_dir"
      /bin/chmod -R u+w "$build_dir"
      cd "$build_dir"

      echo "Building Ghostty 1.3.1-${revision} from ${source}"
      SDKROOT=${lib.escapeShellArg (toString apple-sdk_26.sdkroot)} \
        PATH="${xcrun}/bin:$PATH:/usr/bin:/bin" \
        ${zig_0_15}/bin/zig build --system ${deps} \
          -Dversion-string=1.3.1-${revision}-nix \
          -Doptimize=ReleaseFast \
          -Demit-macos-app=false \
          -Dxcframework-target=native

      (
        cd macos
        /usr/bin/env -i \
          HOME="$HOME" \
          USER="''${USER:-$(/usr/bin/id -un)}" \
          PATH=/usr/bin:/bin:/usr/sbin:/sbin \
          DEVELOPER_DIR="$DEVELOPER_DIR" \
          TMPDIR="''${TMPDIR:-/tmp}" \
          /usr/bin/xcodebuild -target Ghostty -configuration ReleaseLocal -arch ${arch} \
            -disableAutomaticPackageResolution -skipPackageUpdates \
            MARKETING_VERSION=1.3.1
      )

      app="$build_dir/macos/build/ReleaseLocal/Ghostty.app"
      /usr/bin/codesign --verify --deep --strict "$app"
      GHOSTTY_MAC_LAUNCH_SOURCE=cli "$app/Contents/MacOS/ghostty" +version
      ${rsync}/bin/rsync -a --delete "$app/" "$output_dir/Ghostty.app/"
      echo "Built $output_dir/Ghostty.app"
    '';
  }
