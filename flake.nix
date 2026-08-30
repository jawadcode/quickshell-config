{
  description = "My Quickshell Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    systems.url = "github:nix-systems/default";
  };

  outputs = { systems, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      eachSystem = lib.genAttrs (import systems);
    in
    {
      devShells = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [ kdePackages.qtdeclarative ];
            QML2_IMPORT_PATH = builtins.concatStringsSep ":"
              [
                "${pkgs.kdePackages.qtdeclarative}/lib/qt-6/qml"
                "${pkgs.quickshell}/lib/qt-6/qml"
              ];
          };
        });
    };
}
