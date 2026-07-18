{
  description = "Evolving Impressionist TidalCycles runtime";

  inputs.nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/*.tar.gz";

  outputs = { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      tidalGhc = pkgs.haskellPackages.ghcWithPackages (haskellPackages: [
        haskellPackages.tidal
      ]);
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          tidalGhc
          pkgs.cabal-install
        ];
      };
    };
}
