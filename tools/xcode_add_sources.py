#!/usr/bin/env python3
"""Register new Swift files in Legado.xcodeproj.

The Xcode project lists every source file explicitly (no synchronized folder group,
Xcode 14.2 cannot use one). SwiftPM picks files up by directory glob, so `swift build`
and `swift test` keep working without this script — but `xcodebuild` silently ignores
unregistered files, which breaks the iOS build and the release workflow.

Usage:
    python3 tools/xcode_add_sources.py Sources/LegadoCore/Models/Bookmark.swift ...
    python3 tools/xcode_add_sources.py --check          # list unregistered files
    python3 tools/xcode_add_sources.py --remove Sources/LegadoApp/Services/Old.swift
"""

import argparse
import os
import plistlib
import random
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(REPO_ROOT, "Legado.xcodeproj", "project.pbxproj")
GROUP_NAME = "Sources"
SOURCES_PHASE_INDEX = 0  # first build phase of the target is the sources phase


def load():
    with open(PBXPROJ, "rb") as handle:
        return plistlib.load(handle)


def save(project):
    with open(PBXPROJ, "wb") as handle:
        plistlib.dump(project, handle, fmt=plistlib.FMT_XML)


def new_id(objects):
    while True:
        candidate = "%024X" % random.getrandbits(96)
        if candidate not in objects:
            return candidate


def find_group(objects, name):
    for key, value in objects.items():
        if value.get("isa") == "PBXGroup" and value.get("name") == name:
            return key
    raise SystemExit("group %r not found in project" % name)


def find_sources_phase(objects, target_key):
    target = objects[target_key]
    for phase_key in target.get("buildPhases", []):
        if objects[phase_key].get("isa") == "PBXSourcesBuildPhase":
            return phase_key
    raise SystemExit("no PBXSourcesBuildPhase on target")


def find_target(objects, root):
    for key in objects[root]["targets"]:
        if objects[key].get("name") == "LegadoApp":
            return key
    raise SystemExit("LegadoApp target not found")


def referenced_paths(objects):
    return {
        value.get("path")
        for value in objects.values()
        if value.get("isa") == "PBXFileReference" and value.get("path")
    }


def all_swift_files():
    root = os.path.join(REPO_ROOT, "Sources")
    found = []
    for dirpath, _, filenames in os.walk(root):
        for filename in sorted(filenames):
            if filename.endswith(".swift"):
                full = os.path.join(dirpath, filename)
                found.append(os.path.relpath(full, REPO_ROOT))
    return sorted(found)


def check():
    project = load()
    missing = sorted(set(all_swift_files()) - referenced_paths(project["objects"]))
    for path in missing:
        print(path)
    return 1 if missing else 0


def register(paths):
    project = load()
    objects = project["objects"]
    group_key = find_group(objects, GROUP_NAME)
    target_key = find_target(objects, project["rootObject"])
    phase_key = find_sources_phase(objects, target_key)

    already = referenced_paths(objects)
    added = []
    for path in paths:
        if path in already:
            print("skip (already registered): %s" % path)
            continue
        if not os.path.exists(os.path.join(REPO_ROOT, path)):
            print("ERROR: file does not exist: %s" % path, file=sys.stderr)
            return 1

        file_ref = new_id(objects)
        objects[file_ref] = {
            "isa": "PBXFileReference",
            "lastKnownFileType": "sourcecode.swift",
            "path": path,
            "sourceTree": "<group>",
        }
        objects[group_key].setdefault("children", []).append(file_ref)

        build_file = new_id(objects)
        objects[build_file] = {"fileRef": file_ref, "isa": "PBXBuildFile"}
        objects[phase_key].setdefault("files", []).append(build_file)
        added.append(path)
        print("registered: %s" % path)

    if added:
        save(project)
    return 0


def unregister(paths):
    """Inverse of `register`, for deleted features whose files no longer exist."""
    project = load()
    objects = project["objects"]
    group_key = find_group(objects, GROUP_NAME)
    phase_key = find_sources_phase(objects, find_target(objects, project["rootObject"]))
    by_path = {
        value.get("path"): key
        for key, value in objects.items()
        if value.get("isa") == "PBXFileReference"
    }

    removed = []
    for path in paths:
        file_ref = by_path.get(path)
        if file_ref is None:
            print("skip (not registered): %s" % path)
            continue
        build_files = [
            key for key, value in objects.items()
            if value.get("isa") == "PBXBuildFile" and value.get("fileRef") == file_ref
        ]
        for build_file in build_files:
            objects.pop(build_file, None)
            objects[phase_key]["files"] = [f for f in objects[phase_key].get("files", [])
                                           if f != build_file]
        objects.pop(file_ref, None)
        objects[group_key]["children"] = [c for c in objects[group_key].get("children", [])
                                          if c != file_ref]
        removed.append(path)
        print("unregistered: %s" % path)

    if removed:
        save(project)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="paths relative to the ios/ directory")
    parser.add_argument("--check", action="store_true", help="list unregistered Swift files")
    parser.add_argument("--remove", action="store_true",
                        help="drop these paths from the project instead of adding them")
    args = parser.parse_args()

    if args.check:
        return check()
    if not args.paths:
        parser.print_help()
        return 1
    return unregister(args.paths) if args.remove else register(args.paths)


if __name__ == "__main__":
    sys.exit(main())
