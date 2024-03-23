# Copyright © 2023–2024 Hraban Luyat
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, version 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

{
  inputs = {
    cl-nix-lite.url = "github:hraban/cl-nix-lite";
  };

  outputs = {
    self
    , nixpkgs
    , flake-utils
    , cl-nix-lite
  }: {
    # Module to allow darwin hosts to get the timezone name as a string without
    # a password. Insanity but ok. Separate module because it affects different
    # parts of the system and I want all that code grouped together.
    darwinModules = {
      get-timezone = { pkgs, ... }:
        let
          get-timezone-su = pkgs.writeShellScriptBin "get-timezone-su" ''
            /usr/sbin/systemsetup -gettimezone | sed -e 's/[^:]*: //'
          '';
          get-timezone = pkgs.writeShellScriptBin "get-timezone" ''
            sudo ${get-timezone-su}/bin/get-timezone-su
          '';
        in
          {
            assertions = [ {
              assertion = pkgs.stdenv.isDarwin;
              message = "Only available on Darwin";
            } ];
            # This is harmless and honestly it’s a darwin bug that you need admin
            # rights to run this.
            environment = {
              etc."sudoers.d/get-timezone".text = ''
                ALL ALL = NOPASSWD: ${get-timezone-su}/bin/get-timezone-su
              '';
              systemPackages = [ get-timezone ];
            };
          };
      battery-control = let
        clamp-service = { lib, ... }: {
          options = with lib; with types; {
            enable = mkOption {
              type = bool;
              default = false;
              description = "Whether to enable a launch daemon to control the battery charge";
            };
            min = mkOption {
              type = ints.between 0 100;
              default = 50;
              description = "Lowest permissible charge: under this, charging is enabled";
            };
            max = mkOption {
              type = ints.between 0 100;
              default = 80;
              description = "Highest permissible charge: above this, charging is disabled";
            };
          };
        };
        xbar-plugin = { lib, ... }: {
          options = with lib; with types; {
            enable = mkOption {
              type = bool;
              default = false;
              description = "Install a charging toggle in xbar for all users";
            };
          };
        };
      in { lib, pkgs, config, ... }: let
        cfg = config.battery-control;
      in {
        options = with lib; with types; {
          battery-control = {
            clamp-service = mkOption {
              description = "A polling service that toggles charging on/off depending on battery level";
              type = submodule clamp-service;
              default = {};
            };
            xbar-plugin = mkOption {
              description = "A battery charge toggle in xbar";
              type = submodule xbar-plugin;
              default = {};
            };
          };
        };
        config = lib.mkMerge [
          (lib.mkIf cfg.clamp-service.enable {
            assertions = [ {
              assertion = pkgs.stdenv.system == "aarch64-darwin";
              message = "The SMC can only be controlled on aarch64-darwin";
            } ];
            launchd.daemons = {
              poll-smc-charging = {
                serviceConfig = {
                  RunAtLoad = true;
                  StartInterval = 60;
                  ProgramArguments = [
                    (lib.getExe self.packages.${pkgs.system}.clamp-smc-charging)
                    (builtins.toString cfg.clamp-service.min)
                    (builtins.toString cfg.clamp-service.max)
                  ];
                };
              };
            };
          })
          (lib.mkIf cfg.xbar-plugin.enable (let
            inherit (self.packages.${pkgs.system}) xbar-battery-plugin;
          in {
            environment = {
              etc."sudoers.d/home-tools-battery-control".text = pkgs.lib.concatMapStringsSep "\n" (bin: ''
                ALL ALL = NOPASSWD: ${bin}
              '') xbar-battery-plugin.sudo-binaries;
            };
            # Assume home-manager is used.
            home-manager.sharedModules = [ ({ ... }: {
              home.file.xbar-battery-plugin = {
                # The easiest way to copy a binary whose name I don’t know, is to
                # just copy the entire directory recursively, because I know it’s
                # the only binary in there, anyway :)
                source = "${xbar-battery-plugin}/bin/";
                target = "Library/Application Support/xbar/plugins/";
                recursive = true;
                executable = true;
              };
            }) ];
          }))
        ];
      };
    };
    packages = nixpkgs.lib.recursiveUpdate (nixpkgs.lib.genAttrs (with flake-utils.lib.system; [ x86_64-darwin aarch64-darwin ]) (system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.extend cl-nix-lite.overlays.default;
        lpl = pkgs.lispPackagesLite;
      in {
        # Darwin-only because of ‘say’
        alarm = with lpl; lispScript {
          name = "alarm";
          src = ./alarm.lisp;
          dependencies = [
            arrow-macros
            f-underscore
            inferior-shell
            local-time
            trivia
            lpl."trivia.ppcre"
          ];
          installCheckPhase = ''
            $out/bin/alarm --help
          '';
          doInstallCheck = true;
        };
      }
    )) {
      x86_64-darwin =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-darwin.extend cl-nix-lite.overlays.default;
          lpl = pkgs.lispPackagesLite;
        in {
          bclm = pkgs.stdenv.mkDerivation {
            name = "bclm";
            # There’s a copy of this binary included locally en cas de coup dur
            src = pkgs.fetchzip {
              url = "https://github.com/zackelia/bclm/releases/download/v0.0.4/bclm.zip";
              hash = "sha256-3sQhszO+MRLGF5/dm1mFXQZu/MxK3nw68HTpc3cEBOA=";
            };
            installPhase = ''
              mkdir -p $out/bin/
              cp bclm $out/bin/
            '';
            dontFixup = true;
            meta = {
              platforms = [ "x86_64-darwin" ];
              license = pkgs.lib.licenses.mit;
              sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
              downloadPage = "https://github.com/zackelia/bclm/releases";
              mainProgram = "bclm";
            };
          };
          xbar-battery-plugin = let
            bclm = pkgs.lib.getExe self.packages.x86_64-darwin.bclm;
          in with lpl; lispScript {
            name = "battery.30s.lisp";
            src = ./battery.30s.lisp;
            dependencies = [
              arrow-macros
              cl-interpol
              inferior-shell
              trivia
            ];
            inherit bclm;
            passthru.sudo-binaries = [ bclm ];
            postInstall = ''
              export self="$out/bin/$name"
              substituteAllInPlace "$self"
            '';
          };
        };
      aarch64-darwin =
        let
          pkgs = nixpkgs.legacyPackages.aarch64-darwin.extend cl-nix-lite.overlays.default;
          lpl = pkgs.lispPackagesLite;
        in {
          smc = pkgs.stdenvNoCC.mkDerivation {
            name = "smc";
            dontUnpack = true;
            dontPatch = true;
            # I kinda forgot where I got this binary...?
            installPhase = ''
              mkdir -p $out/bin
              cp ${./smc} $out/bin/smc
            '';
            meta = {
              mainProgram = "smc";
              platforms = [ "aarch64-darwin" ];
              sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
            };
          };
          clamp-smc-charging = pkgs.writeShellApplication {
            name = "clamp-smc-charging";
            text = builtins.readFile ./clamp-smc-charging;
            runtimeInputs = [ self.packages.aarch64-darwin.smc ];
            # pmset
            meta.platforms = [ "aarch64-darwin" ];
          };
          xbar-battery-plugin = let
            smc = pkgs.lib.getExe self.packages.aarch64-darwin.smc;
            smc_on = pkgs.writeShellScript "smc_on" ''
              exec ${smc} -k CH0C -w 00
            '';
            smc_off = pkgs.writeShellScript "smc_off" ''
              exec ${smc} -k CH0C -w 01
            '';
          in with lpl; lispScript {
            name = "control-smc.1m.lisp";
            src = ./control-smc.1m.lisp;
            dependencies = [
              cl-interpol
              cl-ppcre
              inferior-shell
              trivia
            ];
            inherit smc smc_on smc_off;
            passthru.sudo-binaries = [ smc_on smc_off ];
            postInstall = ''
              export self="$out/bin/$name"
              substituteAllInPlace "$self"
            '';
          };
        };
    };
  };
}
