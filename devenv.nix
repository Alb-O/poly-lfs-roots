{ pkgs, config, lib, ... }:

let
  cfg = config.lfsRoots;
  pythonBin = lib.getExe pkgs.python3;
  helperScript = ./poly-lfs-roots.py;
  manifestOutputPath = config.outputs.lfs_roots_manifest;
  materializedManifestPath = "${toString config.devenv.root}/${cfg.manifestPath}";
  repoRoot =
    if config.git.root != null
    then config.git.root
    else toString config.devenv.root;
  escape = lib.escapeShellArg;
  rootEnvVarName =
    name: "DVNV_LFS_ROOT_" + lib.toUpper (builtins.replaceStrings [ "-" "." "/" ] [ "_" "_" "_" ] name);
  manifestRoots = lib.mapAttrs (
    name: root: {
      description = root.description;
      envVar =
        if root.envVar != null
        then root.envVar
        else rootEnvVarName name;
      exclude = root.exclude;
      include = root.include;
      path = root.path;
      repoPath = root.repoPath;
    }
  ) cfg.roots;
  manifestData = {
    fetchExclude = cfg.fetch.exclude;
    fetchInclude = cfg.fetch.include;
    remote =
      if cfg.remote == null
      then null
      else {
        lfsurl = cfg.remote.lfsurl;
        lfspushurl = cfg.remote.lfspushurl;
        name = cfg.remote.name;
        setAsDefault = cfg.remote.setAsDefault;
      };
    roots = manifestRoots;
    sharedStorage = cfg.sharedStorage;
    skipSmudge = cfg.skipSmudge;
  };
  rootEnv = lib.mapAttrs' (
    name: root:
    lib.nameValuePair (
      if root.envVar != null then root.envVar else rootEnvVarName name
    ) root.path
  ) (
    lib.filterAttrs (_: root: root.path != null) cfg.roots
  );
  configureExec = ''
    set -euo pipefail

    if ! ${pkgs.git}/bin/git -C ${escape repoRoot} rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      exit 0
    fi

    ${pythonBin} ${helperScript} configure \
      --repo ${escape repoRoot} \
      --manifest ${escape manifestOutputPath}
  '';
in
{
  options.lfsRoots = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable shared Git LFS root orchestration and helper scripts.";
    };

    autoConfigure = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run repo-local Git LFS configuration automatically when entering the shell.";
    };

    manifestPath = lib.mkOption {
      type = lib.types.str;
      default = ".lfs-roots.json";
      description = "Repo-relative path where the generated LFS roots manifest is linked.";
    };

    sharedStorage = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Machine-local shared Git LFS object storage directory to write to `lfs.storage`.";
    };

    skipSmudge = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Export `GIT_LFS_SKIP_SMUDGE=1` inside the development shell.";
    };

    fetch.include = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Default `lfs.fetchinclude` globs to configure in the repo-local Git config.";
    };

    fetch.exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Default `lfs.fetchexclude` globs to configure in the repo-local Git config.";
    };

    remote = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = "origin";
              description = "Remote name whose LFS endpoint should be configured.";
            };

            lfsurl = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Value to write to `remote.<name>.lfsurl`.";
            };

            lfspushurl = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Value to write to `remote.<name>.lfspushurl`.";
            };

            setAsDefault = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Write the remote name into `remote.lfsdefault`.";
            };
          };
        }
      );
      default = null;
      description = "Optional remote-specific Git LFS endpoint configuration.";
    };

    roots = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Short description of what the root contains.";
            };

            path = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Machine-local canonical checkout or mount path for this root.";
            };

            envVar = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Environment variable name to export for this root path. Defaults to `DVNV_LFS_ROOT_<NAME>`.";
            };

            include = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Globs passed to `git lfs pull --include` for this root.";
            };

            repoPath = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Absolute path to the Git checkout that should be used when fetching this root.";
            };

            exclude = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Globs passed to `git lfs pull --exclude` for this root.";
            };
          };
        }
      );
      default = { };
      description = "Named machine-local LFS roots and their fetch filters.";
    };
  };

  config = lib.mkIf cfg.enable {
    env =
      (lib.optionalAttrs cfg.skipSmudge {
        GIT_LFS_SKIP_SMUDGE = "1";
      })
      // rootEnv
      // {
        DVNV_LFS_ROOTS_MANIFEST = materializedManifestPath;
      };

    files."${cfg.manifestPath}".json = manifestData;

    outputs.lfs_roots_manifest = pkgs.writeText "lfs-roots.json" (builtins.toJSON manifestData);

    packages = [ pkgs.git-lfs ];

    scripts = {
      lfs-roots-configure = {
        exec = configureExec;
        description = "Apply repo-local Git LFS settings from the managed poly-lfs-roots manifest.";
      };

      lfs-roots-show = {
        exec = ''
          set -euo pipefail
          ${pythonBin} ${helperScript} show --manifest ${escape manifestOutputPath}
        '';
        description = "Print the managed poly-lfs-roots manifest.";
      };

      lfs-roots-root-path = {
        exec = ''
          set -euo pipefail
          ${pythonBin} ${helperScript} root-path --manifest ${escape manifestOutputPath} "$@"
        '';
        description = "Print the configured machine-local path for a named LFS root.";
      };

      lfs-roots-pull = {
        exec = ''
          set -euo pipefail
          ${pythonBin} ${helperScript} pull-root \
            --repo ${escape repoRoot} \
            --manifest ${escape manifestOutputPath} \
            "$@"
        '';
        description = "Run `git lfs pull` for a named root using its include/exclude globs.";
      };
    };

    tasks = lib.optionalAttrs cfg.autoConfigure {
      "bash:lfs-roots-configure" = {
        before = [ "devenv:enterShell" ];
        exec = configureExec;
      };
    };
  };
}
