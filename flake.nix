# Copyright © 2023  Hraban Luyat
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
      xbar-battery-plugin = { pkgs, config, ... }:
        let
          inherit (self.packages.${pkgs.system}) battery;
        in {
          assertions = [ {
            assertion = pkgs.stdenv.system == "x86_64-darwin";
            message = "The BCLM binary only works on x86_64-darwin";
          } ];
          environment = {
            etc."sudoers.d/bclm".text = ''
              ALL ALL = NOPASSWD: ${battery.bclm}
            '';
          };
          # Assume home-manager is used.
          home-manager.users = pkgs.lib.genAttrs config.users.knownUsers (name: {
            home.file.xbar-battery-plugin = {
              source = "${battery}/bin/battery.30s.lisp";
              target = "Library/Application Support/xbar/plugins/battery.30s.lisp";
              executable = true;
            };
          });
        };
    };
  } // {
    packages = nixpkgs.lib.genAttrs (with flake-utils.lib.system; [ x86_64-darwin aarch64-darwin ]) (system:
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
    ) // {
      x86_64-darwin =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-darwin.extend cl-nix-lite.overlays.default;
          lpl = pkgs.lispPackagesLite;
        in {
          battery = with lpl; lispScript {
            name = "battery.30s.lisp";
            src = ./battery.30s.lisp;
            dependencies = [
              arrow-macros
              cl-interpol
              cl-json
              inferior-shell
            ];
            bclm = "${self.packages.x86_64-darwin.bclm}/bin/bclm";
            postInstall = ''
              export self="$out/bin/$name"
              substituteAllInPlace "$self"
            '';
          };
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
            };
          };
        };
    };
  };
}
