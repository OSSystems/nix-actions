{
  description = "nix-actions regression fixture";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAll (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          pkgA = pkgs.runCommand "fixture-pkg-a" { } "echo a > $out";
          pkgB = pkgs.runCommand "fixture-pkg-b" { } "echo b > $out";
        }
      );

      devShells = forAll (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShellNoCC { packages = [ pkgs.coreutils ]; };
          ci = pkgs.mkShellNoCC {
            packages = [
              pkgs.jq
              pkgs.hello
            ];
            NIX_ACTION_DEVELOP_SENTINEL = "loaded";
          };
        }
      );

      nixosConfigurations.testhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            boot.isContainer = true;
            system.stateVersion = "24.11";
          }
        ];
      };

      githubActions.matrix.include = [
        {
          name = "pkgA";
          attr = "packages.x86_64-linux.pkgA";
        }
        {
          name = "pkgB";
          attr = "packages.x86_64-linux.pkgB";
        }
      ];

      checks = forAll (system: {
        trivial = (pkgsFor system).runCommand "fixture-check" { } "echo ok > $out";
      });
    };
}
