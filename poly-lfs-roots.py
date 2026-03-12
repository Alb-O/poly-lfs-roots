#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path


def load_manifest(path_str):
    path = Path(path_str)
    with path.open("r", encoding="utf-8") as handle:
        parsed = json.load(handle) or {}

    if not isinstance(parsed, dict):
        raise SystemExit("expected top-level object in LFS roots manifest")

    parsed.setdefault("roots", {})
    parsed.setdefault("fetchInclude", [])
    parsed.setdefault("fetchExclude", [])
    return parsed


def git(repo, *args, check=True, capture_output=False):
    return subprocess.run(
        ["git", "-C", repo, *args],
        check=check,
        text=True,
        capture_output=capture_output,
    )


def git_get_all(repo, key):
    result = git(repo, "config", "--local", "--get-all", key, check=False, capture_output=True)
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def git_set(repo, key, value):
    current = git_get_all(repo, key)
    desired = [] if value is None else [value]

    if current == desired:
        return False

    if current:
        git(repo, "config", "--local", "--unset-all", key)

    if value is not None:
        git(repo, "config", "--local", key, value)

    return True


def join_globs(values):
    cleaned = [value for value in values if isinstance(value, str) and value]
    if not cleaned:
        return None
    return ",".join(cleaned)


def configure(args):
    manifest = load_manifest(args.manifest)
    repo = args.repo
    changes = []

    shared_storage = manifest.get("sharedStorage")
    if git_set(repo, "lfs.storage", shared_storage):
        changes.append("lfs.storage")

    fetch_include = join_globs(manifest.get("fetchInclude", []))
    if git_set(repo, "lfs.fetchinclude", fetch_include):
        changes.append("lfs.fetchinclude")

    fetch_exclude = join_globs(manifest.get("fetchExclude", []))
    if git_set(repo, "lfs.fetchexclude", fetch_exclude):
        changes.append("lfs.fetchexclude")

    remote = manifest.get("remote")
    if isinstance(remote, dict):
        name = remote.get("name")
        if isinstance(name, str) and name:
            if git_set(repo, f"remote.{name}.lfsurl", remote.get("lfsurl")):
                changes.append(f"remote.{name}.lfsurl")
            if git_set(repo, f"remote.{name}.lfspushurl", remote.get("lfspushurl")):
                changes.append(f"remote.{name}.lfspushurl")
            if remote.get("setAsDefault"):
                if git_set(repo, "remote.lfsdefault", name):
                    changes.append("remote.lfsdefault")

    if changes:
        print("updated:", ", ".join(changes))


def show(args):
    manifest = load_manifest(args.manifest)
    json.dump(manifest, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def root_path(args):
    manifest = load_manifest(args.manifest)
    roots = manifest.get("roots", {})
    root = roots.get(args.name)
    if not isinstance(root, dict):
        raise SystemExit(f"unknown LFS root '{args.name}'")

    path = root.get("path")
    if not isinstance(path, str) or not path:
        raise SystemExit(f"LFS root '{args.name}' does not have a configured path")

    print(path)


def pull_root(args):
    manifest = load_manifest(args.manifest)
    roots = manifest.get("roots", {})
    root = roots.get(args.name)
    if not isinstance(root, dict):
        raise SystemExit(f"unknown LFS root '{args.name}'")

    include = join_globs(root.get("include", [])) or join_globs(manifest.get("fetchInclude", []))
    exclude = join_globs(root.get("exclude", [])) or join_globs(manifest.get("fetchExclude", []))
    repo = root.get("repoPath")
    if not isinstance(repo, str) or not repo:
        repo = args.repo

    command = ["git", "-C", repo, "lfs", "pull"]
    if args.remote:
        command.append(args.remote)
    if include is not None:
        command.extend(["--include", include])
    if exclude is not None:
        command.extend(["--exclude", exclude])

    subprocess.run(command, check=True)


def build_parser():
    parser = argparse.ArgumentParser(description="Manage poly-lfs-roots manifests and repo-local Git LFS config.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    configure_parser = subparsers.add_parser("configure", help="Apply repo-local Git LFS config from the manifest.")
    configure_parser.add_argument("--manifest", required=True)
    configure_parser.add_argument("--repo", required=True)
    configure_parser.set_defaults(func=configure)

    show_parser = subparsers.add_parser("show", help="Print the manifest as formatted JSON.")
    show_parser.add_argument("--manifest", required=True)
    show_parser.set_defaults(func=show)

    root_path_parser = subparsers.add_parser("root-path", help="Print the configured path for one root.")
    root_path_parser.add_argument("--manifest", required=True)
    root_path_parser.add_argument("name")
    root_path_parser.set_defaults(func=root_path)

    pull_parser = subparsers.add_parser("pull-root", help="Run git lfs pull using the named root's filters.")
    pull_parser.add_argument("--manifest", required=True)
    pull_parser.add_argument("--repo", required=True)
    pull_parser.add_argument("name")
    pull_parser.add_argument("remote", nargs="?")
    pull_parser.set_defaults(func=pull_root)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
