# poly-lfs-roots

Reusable `devenv` module for machine-local Git LFS root orchestration in the
polyrepo.

The module is intentionally focused on coordination, not blob storage:

- configure repo-local Git LFS settings on shell entry
- expose machine-local canonical asset root paths through env vars
- materialize a repo-local JSON manifest describing configured roots
- provide helper scripts for inspecting roots and fetching selected slices

## Includes

- `lfsRoots.*` options
- Materialized file: `.lfs-roots.json` (configurable)
- Output: `outputs.lfs_roots_manifest`
- Scripts:
  - `lfs-roots-configure`
  - `lfs-roots-show`
  - `lfs-roots-root-path`
  - `lfs-roots-pull`

## Use

```yaml
inputs:
  poly-lfs-roots:
    url: github:Alb-O/poly-lfs-roots
    flake: false
imports:
  - poly-lfs-roots
```

Then opt into machine-local configuration in `devenv.local.nix`:

```nix
{
  lfsRoots = {
    enable = true;
    sharedStorage = "/home/albert/.local/share/poly/git-lfs";
    remote = {
      name = "asset-store";
      lfsurl = "ssh://asset-store.example/srv/git-lfs/nusim.git/info/lfs";
      setAsDefault = true;
    };
    roots = {
      models = {
        repoPath = "/home/albert/lfs/assets";
        path = "/home/albert/lfs/assets/models";
        include = [ "models/**" ];
      };
      textures = {
        repoPath = "/home/albert/lfs/assets";
        path = "/home/albert/lfs/assets/textures";
        include = [ "textures/**" ];
      };
    };
  };
}
```

## Notes

- `lfsRoots` only writes repo-local Git config. It does not touch
  `~/.gitconfig`.
- `sharedStorage` points multiple repos at one LFS object store, but checked-out
  working tree files are still separate. Use canonical asset root checkouts plus
  env vars or custom asset sources to avoid duplicate materialization.
- `lfs-roots-pull <name>` is intended for slice fetches using the root's
  include/exclude globs. If `repoPath` is set, the pull runs in that external
  checkout instead of the consumer repo.
