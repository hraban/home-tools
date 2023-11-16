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
    darwinModules.get-timezone = { pkgs, ... }:
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
  } // (with flake-utils.lib; eachSystem [ system.x86_64-darwin system.aarch64-darwin ] (system: {
    packages =
      let
        pkgs = nixpkgs.legacyPackages.${system}.extend cl-nix-lite.overlays.default;
        lpp = pkgs.lispPackagesLite;
      in {
        # Darwin-only because of ‘say’
        alarm = with lpp; lispScript {
          name = "alarm";
          src = ./alarm.lisp;
          dependencies = [
            arrow-macros
            f-underscore
            inferior-shell
            local-time
            trivia
            lpp."trivia.ppcre"
          ];
          installCheckPhase = ''
            $out/bin/alarm --help
          '';
          doInstallCheck = true;
        };
      };
    }));
}
