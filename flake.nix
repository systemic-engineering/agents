{
  description = "systemic-engineer/agents — reproducible environments for agent invocations";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Shared tools available in all environments
        baseTools = [
          pkgs.git
          pkgs.just
          pkgs.jq
          pkgs.sops
          pkgs.gnupg
          pkgs.curl
          pkgs.dhall
          pkgs.dhall-json
        ];

        # BEAM / Elixir stack
        beamPkgs = pkgs.beam.packages.erlang_27;
        elixir   = beamPkgs.elixir_1_18;

        elixirTools = [
          elixir
          pkgs.erlang_27
          beamPkgs.rebar3
          pkgs.mix2nix
        ];

        baseShellHook = ''
          export LANG=en_US.UTF-8
        '';

        # Glue sidecar script — bundled in the nix store so it's always findable
        glueSidecar = pkgs.writeText "glue-sidecar.exs"
          (builtins.readFile ./glue/sidecar.exs);

        glueShellHook = ''
          # ── Glue sidecar ────────────────────────────────────────────────────
          export GLUE_NODE="''${GLUE_NODE:-glue@Alexs-MacBook-Pro}"
          # Installed release takes precedence; fall back to dev build
          if [ -f "''${HOME}/.local/libexec/glue/bin/glue" ]; then
            export GLUE_BIN="''${HOME}/.local/libexec/glue/bin/glue"
            export GLUE_COOKIE="$(cat ''${HOME}/.local/libexec/glue/releases/COOKIE 2>/dev/null || echo glue_local)"
          elif [ -f "/Users/alexwolf/dev/projects/glue/_build/prod/rel/glue/bin/glue" ]; then
            export GLUE_BIN="/Users/alexwolf/dev/projects/glue/_build/prod/rel/glue/bin/glue"
            export GLUE_COOKIE="$(cat /Users/alexwolf/dev/projects/glue/_build/prod/rel/glue/releases/COOKIE 2>/dev/null || echo glue_local)"
          else
            export GLUE_BIN=""
            export GLUE_COOKIE="glue_local"
          fi
          export GLUE_WORKER="''${GLUE_WORKER:-agent-$$}"
          export GLUE_CHANNEL="''${GLUE_CHANNEL:-session-$$}"
          export GLUE_EVENT_LOG="/tmp/glue-events-$$.log"

          # Shell functions — exported so subshells inherit them
          glue-recv()    { tail -f "$GLUE_EVENT_LOG" 2>/dev/null; }
          glue-status()  {
            if "$GLUE_BIN" rpc "IO.puts(node())" 2>/dev/null; then echo "glue: up"
            else echo "glue: unreachable"; fi
          }
          glue-chatter() {
            local msg="$1"
            "$GLUE_BIN" rpc "Glue.Dispatch.dispatch(Glue.Events.chatter(Glue.Channel.new(\"$GLUE_CHANNEL\"), Glue.Worker.new(\"$GLUE_WORKER\"), Glue.Message.new(\"$msg\"), DateTime.utc_now()))"
          }
          glue-dm() {
            local target="$1" msg="$2"
            "$GLUE_BIN" rpc "Glue.Dispatch.send_to(Glue.Worker.new(\"$target\"), Glue.Events.dm(Glue.Channel.new(\"$GLUE_CHANNEL\"), Glue.Worker.new(\"$GLUE_WORKER\"), Glue.Worker.new(\"$target\"), Glue.Message.new(\"$msg\"), DateTime.utc_now()))"
          }
          export -f glue-recv glue-status glue-chatter glue-dm

          # Start sidecar in background if glue binary is available
          if [ -n "$GLUE_BIN" ] && [ -f "$GLUE_BIN" ]; then
            GLUE_NODE="$GLUE_NODE" \
            GLUE_COOKIE="$GLUE_COOKIE" \
            GLUE_WORKER="$GLUE_WORKER" \
            GLUE_CHANNEL="$GLUE_CHANNEL" \
            GLUE_EVENT_LOG="$GLUE_EVENT_LOG" \
            elixir --sname "glue-sidecar-$$" --cookie "$GLUE_COOKIE" ${glueSidecar} \
              2>/tmp/glue-sidecar-$$.log &
            _GLUE_SIDECAR_PID=$!
            echo "glue: sidecar started (pid $_GLUE_SIDECAR_PID, worker=$GLUE_WORKER)"
          else
            echo "glue: daemon not installed — sidecar skipped (install with: just install in glue repo)"
          fi

          trap '
            [ -n "$_GLUE_SIDECAR_PID" ] && kill "$_GLUE_SIDECAR_PID" 2>/dev/null
            rm -f "$GLUE_EVENT_LOG"
          ' EXIT
          # ────────────────────────────────────────────────────────────────────
        '';

        elixirShellHook = baseShellHook + ''
          export MIX_HOME=$PWD/.nix-mix
          export MIX_REBAR3=${beamPkgs.rebar3}/bin/rebar3
          export HEX_HOME=$PWD/.nix-hex
          export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
        '' + glueShellHook;

      in {
        devShells = {
          # ── base ─────────────────────────────────────────────────────────────
          # Minimal agent environment: git, just, sops, jq, dhall.
          # Use this when the project provides its own language runtime.
          #
          #   nix develop github:systemic-engineer/agents#base
          default = pkgs.mkShell {
            buildInputs = baseTools;
            shellHook   = baseShellHook;
          };

          base = pkgs.mkShell {
            buildInputs = baseTools;
            shellHook   = baseShellHook;
          };

          # ── elixir ───────────────────────────────────────────────────────────
          # Elixir 1.18 / OTP 27 + base tools.
          # Use for any BEAM project without pinned deps.
          #
          #   nix develop github:systemic-engineer/agents#elixir
          elixir = pkgs.mkShell {
            buildInputs = baseTools ++ elixirTools;
            shellHook   = elixirShellHook;
          };
        };
      });
}
