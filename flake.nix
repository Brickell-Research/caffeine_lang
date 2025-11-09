{
  description = "caffeine_lang packaged with Nix (using nix-gleam, Gleam 1.13.0)";

  inputs = {
    # Pin to a nixpkgs rev that includes gleam 1.13.0
    nixpkgs.url     = "github:NixOS/nixpkgs/a7fc11be66bdfb5cdde611ee5ce381c183da8386";
    flake-utils.url = "github:numtide/flake-utils";
    nix-gleam.url   = "github:arnarg/nix-gleam";
  };

  outputs = { self, nixpkgs, flake-utils, nix-gleam, ... }:
    flake-utils.lib.eachSystem
      [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ nix-gleam.overlays.default ];
          };
        in {
          # The package (derivation) that builds your Gleam app.
          # We use a custom build instead of buildGleamApplication to avoid tree-shaking
          packages.caffeine = pkgs.stdenv.mkDerivation {
            pname = "caffeine_lang";
            version = "0.0.38";
            src = ./.;

            nativeBuildInputs = [ pkgs.gleam pkgs.erlang pkgs.rebar3 ];
            
            buildPhase = ''
              runHook preBuild
              HOME=$TMPDIR gleam build --target erlang
              runHook postBuild
            '';
            
            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib $out/bin
              
              # Copy all packages preserving the structure: lib/<package>/ebin/
              for pkg_dir in build/dev/erlang/*/; do
                pkg_name=$(basename "$pkg_dir")
                if [ -d "$pkg_dir/ebin" ]; then
                  mkdir -p "$out/lib/$pkg_name"
                  cp -r "$pkg_dir/ebin" "$out/lib/$pkg_name/"
                  # Also copy include directories if they exist
                  if [ -d "$pkg_dir/include" ]; then
                    cp -r "$pkg_dir/include" "$out/lib/$pkg_name/" 2>/dev/null || true
                  fi
                fi
              done
              
              # Create wrapper script
              cat > $out/bin/caffeine_lang << EOF
#!/bin/sh
exec ${pkgs.erlang}/bin/erl -pa $out/lib/*/ebin -eval "caffeine_lang@@main:run(caffeine_lang)" -noshell -extra "\$@"
EOF
              chmod +x $out/bin/caffeine_lang
              runHook postInstall
            '';
          };

          # Make `nix build` with no attr select do the right thing.
          packages.default = self.packages.${system}.caffeine;

          # `nix run` support
          apps.default = {
            type = "app";
            program = "${self.packages.${system}.caffeine}/bin/caffeine";
          };

          # Dev shell with matching toolchain
          devShells.default = pkgs.mkShell {
            buildInputs = [
              pkgs.gleam       # 1.13.0 via the nixpkgs pin above
              pkgs.erlang_26
              pkgs.rebar3
            ];
          };
        });
}
