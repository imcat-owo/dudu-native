#!/usr/bin/env python3
"""Sync Dudu.xcodeproj/project.pbxproj with the Swift files under Dudu/.

Idempotent: UUIDs are deterministic (md5 of the relative path), so running
this twice produces no diff. Builders: copy .swift files into Dudu/<subdir>/,
then run:  python3 scripts/sync_pbxproj.py

Also supports wiring a local SwiftPM package:
  python3 scripts/sync_pbxproj.py --add-local-package BridgeCore BridgeCore BridgeCore
  (args: <package-name> <relative-path-from-project-root> <product-name>)
"""
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.join(ROOT, "Dudu.xcodeproj", "project.pbxproj")
SRC_DIR = os.path.join(ROOT, "Dudu")

TARGET_ID = "100000000000000000000002"   # PBXNativeTarget "Dudu"
DUDU_GROUP_ID = "100000000000000000000007"  # PBXGroup path=Dudu
SOURCES_PHASE_ID = "100000000000000000000003"


def uuid_for(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def find_section(text, name):
    """Return (start_idx, end_idx) of a section body, or None."""
    begin = f"/* Begin {name} section */"
    end = f"/* End {name} section */"
    bi = text.find(begin)
    ei = text.find(end)
    if bi < 0 or ei < 0:
        return None
    return bi + len(begin), ei


def ensure_section(text, name):
    rng = find_section(text, name)
    if rng:
        return text
    # Insert a new empty section right before the objects dict closes.
    anchor = "\t};\n\trootObject"
    ins = f"\n/* Begin {name} section */\n/* End {name} section */\n"
    assert anchor in text, "cannot find objects close anchor"
    return text.replace(anchor, ins + anchor, 1)


def section_has(text, name, obj_id):
    rng = find_section(text, name)
    if not rng:
        return False
    body = text[rng[0]:rng[1]]
    return f"\t\t{obj_id} " in body or f"\t\t{obj_id}/" in body


def append_to_section(text, name, entry):
    text = ensure_section(text, name)
    rng = find_section(text, name)
    body = text[rng[0]:rng[1]]
    return text[:rng[0]] + body + entry + text[rng[1]:]


def get_object_block(text, obj_id):
    """Return (full_match_start, full_match_end, inner_text) for an object."""
    # Match the definition line only: anchored at line start so references
    # inside children/files arrays (deeper indent) never match. The comment
    # class [^\n]* keeps it on one line.
    pat = re.compile(
        r"^\t\t" + re.escape(obj_id) + r" /\*[^\n]*\*/ = \{\n(.*?)\n\t\t\};",
        re.M | re.S)
    m = pat.search(text)
    if not m:
        return None
    return m.start(), m.end(), m.group(1)


def set_array_field(text, obj_id, field, items):
    """Replace `field = ( ... );` inside an object block with items list."""
    loc = get_object_block(text, obj_id)
    assert loc, f"object {obj_id} not found"
    s, e, inner = loc
    lines = "".join(f"\n\t\t\t\t{item}," for item in items)
    new_inner, n = re.subn(
        field + r" = \(\n.*?\n\t\t\t\);",
        field + " = (" + lines + "\n\t\t\t);",
        inner, flags=re.S)
    assert n == 1, f"field {field} not found exactly once in {obj_id}"
    return text[:s] + text[s:e].replace(inner, new_inner) + text[e:]


def sync_sources():
    with open(PROJ) as f:
        text = f.read()

    # Collect swift files: rel -> (dir_rel, filename)
    files = {}
    for dirpath, _, filenames in os.walk(SRC_DIR):
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT)          # Dudu/Shared/Foo.swift
            dir_rel = os.path.relpath(dirpath, ROOT)   # Dudu/Shared
            files[rel] = (dir_rel, fn)

    # Build dir tree: dir_rel -> (subdirs, files)
    dirs = {}
    for rel, (dir_rel, fn) in files.items():
        parts = dir_rel.split(os.sep)  # ['Dudu', 'Shared', ...]
        for i in range(1, len(parts) + 1):
            d = os.sep.join(parts[:i])
            dirs.setdefault(d, {"subdirs": set(), "files": []})
        dirs[dir_rel]["files"].append((rel, fn))
        if len(parts) > 1:
            parent = os.sep.join(parts[:-1])
            dirs[parent]["subdirs"].add(dir_rel)

    # Ensure PBXGroup for every dir (except Dudu root which already exists)
    for dir_rel in sorted(dirs):
        if dir_rel == "Dudu":
            continue
        gid = uuid_for("group:" + dir_rel)
        if not section_has(text, "PBXGroup", gid):
            name = os.path.basename(dir_rel)
            entry = (f"\t\t{gid} /* {name} */ = {{\n"
                     f"\t\t\tisa = PBXGroup;\n"
                     f"\t\t\tchildren = (\n\t\t\t);\n"
                     f"\t\t\tpath = {name};\n"
                     f"\t\t\tsourceTree = \"<group>\";\n"
                     f"\t\t}};\n")
            text = append_to_section(text, "PBXGroup", entry)

    # Ensure file refs + build files, collect children per dir and phase files
    phase_files = []
    dir_children = {d: [] for d in dirs}
    for rel in sorted(files):
        dir_rel, fn = files[rel]
        fr_id = uuid_for("fileref:" + rel)
        bf_id = uuid_for("buildfile:" + rel)
        if not section_has(text, "PBXFileReference", fr_id):
            entry = (f"\t\t{fr_id} /* {fn} */ = {{isa = PBXFileReference; "
                     f"lastKnownFileType = sourcecode.swift; path = {fn}; "
                     f'sourceTree = "<group>"; }};\n')
            text = append_to_section(text, "PBXFileReference", entry)
        if not section_has(text, "PBXBuildFile", bf_id):
            entry = (f"\t\t{bf_id} /* {fn} in Sources */ = {{isa = PBXBuildFile; "
                     f"fileRef = {fr_id} /* {fn} */; }};\n")
            text = append_to_section(text, "PBXBuildFile", entry)
        dir_children[dir_rel].append(f"{fr_id} /* {fn} */")
        phase_files.append(f"{bf_id} /* {fn} in Sources */")

    # Set children for each group (subdirs first, then files)
    for dir_rel in sorted(dirs):
        if dir_rel == "Dudu":
            gid = DUDU_GROUP_ID
        else:
            gid = uuid_for("group:" + dir_rel)
        children = []
        for sub in sorted(dirs[dir_rel]["subdirs"]):
            children.append(f"{uuid_for('group:' + sub)} /* {os.path.basename(sub)} */")
        children.extend(sorted(dir_children[dir_rel]))
        text = set_array_field(text, gid, "children", children)

    # Set Sources build phase files
    text = set_array_field(text, SOURCES_PHASE_ID, "files", sorted(phase_files))

    with open(PROJ, "w") as f:
        f.write(text)
    print(f"synced {len(files)} swift files into project.pbxproj")


def add_local_package(name, relpath, product):
    with open(PROJ) as f:
        text = f.read()
    pkg_id = uuid_for("localpkg:" + name)
    dep_id = uuid_for("pkgdep:" + name + ":" + product)

    if not section_has(text, "XCLocalSwiftPackageReference", pkg_id):
        entry = (f"\t\t{pkg_id} /* {name} */ = {{\n"
                 f"\t\t\tisa = XCLocalSwiftPackageReference;\n"
                 f"\t\t\trelativePath = {relpath};\n"
                 f"\t\t}};\n")
        text = append_to_section(text, "XCLocalSwiftPackageReference", entry)
        print(f"added XCLocalSwiftPackageReference {name} -> {relpath}")
    else:
        print(f"package ref {name} already present")

    if not section_has(text, "XCSwiftPackageProductDependency", dep_id):
        entry = (f"\t\t{dep_id} /* {product} */ = {{\n"
                 f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
                 f"\t\t\tpackage = {pkg_id} /* {name} */;\n"
                 f"\t\t\tproductName = {product};\n"
                 f"\t\t}};\n")
        text = append_to_section(text, "XCSwiftPackageProductDependency", entry)
        print(f"added XCSwiftPackageProductDependency {product}")
    else:
        print(f"product dep {product} already present")

    # Attach to target's packageProductDependencies
    loc = get_object_block(text, TARGET_ID)
    assert loc, "target not found"
    s, e, inner = loc
    dep_entry = f"{dep_id} /* {product} */"
    if "packageProductDependencies" in inner:
        m = re.search(r"packageProductDependencies = \(\n(.*?)\n\t\t\t\);", inner, re.S)
        assert m, "malformed packageProductDependencies"
        existing = m.group(1)
        if dep_id not in existing:
            new_list = existing + f",\n\t\t\t\t{dep_entry}"
            inner = inner.replace(m.group(0),
                f"packageProductDependencies = ({new_list}\n\t\t\t);")
            text = text[:s] + text[s:e].replace(loc[2], inner) + text[e:]
            print("attached product dep to target")
        else:
            print("product dep already attached to target")
    else:
        inner = inner.rstrip() + (
            f"\n\t\t\tpackageProductDependencies = (\n"
            f"\t\t\t\t{dep_entry},\n\t\t\t);")
        # re-emit block: rebuild from s..e with new inner
        head_end = text[s:e].find("{\n") + 2
        text = text[:s] + text[s:s+head_end] + inner + "\n\t\t};" + text[e:]
        print("created packageProductDependencies on target")

    with open(PROJ, "w") as f:
        f.write(text)


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "--add-local-package":
        add_local_package(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) == 1:
        sync_sources()
    else:
        sys.exit("usage: sync_pbxproj.py [--add-local-package <name> <relpath> <product>]")
