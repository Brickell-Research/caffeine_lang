{
  description = "Caffeine DSL compiler — generates reliability artifacts from service expectation definitions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        erlang = pkgs.erlang_27;
        gleam = pkgs.gleam;
        rebar3 = pkgs.rebar3;

        version = "4.7.5";

        # Build the erlang-shipment: precompiled BEAM files + entrypoint
        caffeine-shipment = pkgs.stdenv.mkDerivation {
          pname = "caffeine-shipment";
          inherit version;
          src = pkgs.lib.cleanSource ./.;

          nativeBuildInputs = [ gleam erlang rebar3 ];

          # Gleam needs a writable HOME for its cache
          buildPhase = ''
            export HOME=$(mktemp -d)
            cd caffeine_cli
            gleam export erlang-shipment
          '';

          installPhase = ''
            mkdir -p $out
            cp -r build/erlang-shipment/* $out/
          '';
        };

        # Wrap the shipment into a package with a bin/caffeine script
        caffeine = pkgs.stdenv.mkDerivation {
          pname = "caffeine";
          inherit version;
          src = caffeine-shipment;

          dontBuild = true;

          installPhase = ''
            mkdir -p $out/lib/caffeine $out/bin
            cp -r $src/* $out/lib/caffeine/

            cat > $out/bin/caffeine << 'WRAPPER'
            #!/bin/sh
            exec ${erlang}/bin/erl \
              -pa "$(dirname "$0")/../lib/caffeine"/*/ebin \
              -eval "caffeine_cli@@main:run(caffeine_cli)" \
              -noshell \
              -extra "$@"
            WRAPPER
            chmod +x $out/bin/caffeine
          '';
        };

      in {
        packages = {
          default = caffeine;
          shipment = caffeine-shipment;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            gleam
            erlang
            rebar3
            pkgs.bun          # browser bundle (esbuild via bunx)
            pkgs.nodejs_20    # JS target tests
          ];

          shellHook = ''
            echo "Caffeine dev shell — Gleam $(gleam --version), Erlang/OTP ${erlang.version}"
          '';
        };
      }
    );
}
