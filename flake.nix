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
          packages.caffeine = pkgs.buildGleamApplication {
            # If pname/version/target are in gleam.toml, you can omit them.
            # You can also override them here:
            pname = "caffeine_lang";
            # version = "0.0.32";
            # target = "erlang";
            src = ./.;

            # If you need native deps, add:
            # buildInputs = [ pkgs.openssl pkgs.zlib ];

            # Pick Erlang/OTP if you want a specific one (otherwise default from nixpkgs):
            # erlangPackage = pkgs.erlang_26;

            # If rebar plugins are needed:
            # rebar3Package = pkgs.rebar3WithPlugins { plugins = with pkgs.beamPackages; [ pc ]; };
            
            # Override the wrapper script to call main/0 instead of run/1
            postInstall = ''
              # Replace the generated wrapper with one that calls main/0
              cat > $out/bin/caffeine_lang << 'EOF'
#!/bin/sh
exec ${pkgs.erlang}/bin/erl -pa $out/lib/*/ebin -eval "caffeine_lang@@main:main(), halt()" -noshell -extra "$@"
EOF
              chmod +x $out/bin/caffeine_lang
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
