#!/usr/bin/env python3
"""Sync Dudu.xcodeproj/project.pbxproj with the source files under Dudu/.

Idempotent: UUIDs are deterministic (md5 of the relative path), so running
this twice produces no diff. Builders: copy files into Dudu/<subdir>/,
then run:  python3 scripts/sync_pbxproj.py

What gets synced:
  - .swift/.m/.mm            -> target Sources build phase
  - .h/.hpp                  -> file refs only (project navigator)
  - .tiktoken/.utf8/.md      -> target Resources build phase
  - EXCLUDE                  -> files ported to disk but not yet buildable
                               (missing cross-part types); they get file refs
                               but no build phase entry. Remove entries as
                               their owning parts land.

Also ensures the Dudu target's build settings carry the bridging header and
the cppjieba header search path (needed by Shared/JiebaWrapper.mm).

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
RESOURCES_PHASE_ID = "100000000000000000000004"
TARGET_CONFIG_IDS = [  # XCBuildConfiguration for PBXNativeTarget "Dudu"
    "100000000000000000000016",  # Debug
    "100000000000000000000017",  # Release
]
BRIDGING_HEADER = "$(SRCROOT)/Dudu/Dudu-Bridging-Header.h"
CPPJIEBA_INCLUDE = "$(SRCROOT)/Dudu/Vendor/cppjieba/include"

# Files ported to disk but NOT compiled yet: they reference types owned by
# later parts. They still get file refs (visible in the navigator).
#   P3 (Providers) re-enables: ConfigRegistry+Builtins, Collections/{Providers,
#     Models, Groups, ThinkingRules} + reverts the builtinsRegistrar seam in
#     Config/ConfigRegistry.swift to the direct Self.registerBuiltins call.
#   P4 (chat core, SoulStore) re-enables: AppearanceStudio/ThemePack/ThemeLibrary.
EXCLUDE = {
    "Dudu/Shared/Config/ConfigRegistry+Builtins.swift",
    "Dudu/Shared/Config/Collections/ProvidersCollection.swift",
    "Dudu/Shared/Config/Collections/ModelsCollection.swift",
    "Dudu/Shared/Config/Collections/GroupsCollection.swift",
    "Dudu/Shared/Config/Collections/ThinkingRulesCollection.swift",
    "Dudu/Shared/AppearanceStudio.swift",
    "Dudu/Shared/AppearanceThemePack.swift",
    "Dudu/Shared/AppearanceThemeLibrary.swift",
}

SOURCE_EXTS = {".swift", ".m", ".mm"}
HEADER_EXTS = {".h", ".hpp"}
RESOURCE_EXTS = {".tiktoken", ".utf8", ".md"}

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".m": "sourcecode.c.objc",
    ".mm": "sourcecode.cpp.objcpp",
    ".h": "sourcecode.c.h",
    ".hpp": "sourcecode.cpp.h",
    ".tiktoken": "text",
    ".utf8": "text",
    ".md": "text",
}


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
        field + r" = \(\n(.*?\n)?\t\t\t\);",
        field + " = (" + lines + "\n\t\t\t);",
        inner, flags=re.S)
    assert n == 1, f"field {field} not found exactly once in {obj_id}"
    return text[:s] + text[s:e].replace(inner, new_inner) + text[e:]


def current_phase_entries(text, phase_id):
    """Raw `files` entries currently in a build phase (no trailing commas)."""
    loc = get_object_block(text, phase_id)
    if not loc:
        return []
    m = re.search(r"files = \(\n(.*?)\n\t\t\t\);", loc[2], re.S)
    if not m:
        return []
    return [ln.strip().rstrip(",") for ln in m.group(1).splitlines()
            if ln.strip()]


def kind_of(fn):
    ext = os.path.splitext(fn)[1].lower()
    if ext in SOURCE_EXTS:
        return "source"
    if ext in HEADER_EXTS:
        return "header"
    if ext in RESOURCE_EXTS:
        return "resource"
    return None


def sync_sources():
    with open(PROJ) as f:
        text = f.read()

    # Collect files: rel -> (dir_rel, filename, kind)
    files = {}
    for dirpath, _, filenames in os.walk(SRC_DIR):
        for fn in filenames:
            kind = kind_of(fn)
            if kind is None:
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT)          # Dudu/Shared/Foo.swift
            dir_rel = os.path.relpath(dirpath, ROOT)   # Dudu/Shared
            files[rel] = (dir_rel, fn, kind)

    # Build dir tree: dir_rel -> (subdirs, files)
    dirs = {}
    for rel, (dir_rel, fn, kind) in files.items():
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
    resource_files = []
    dir_children = {d: [] for d in dirs}
    for rel in sorted(files):
        dir_rel, fn, kind = files[rel]
        fr_id = uuid_for("fileref:" + rel)
        bf_id = uuid_for("buildfile:" + rel)
        ftype = FILE_TYPES[os.path.splitext(fn)[1].lower()]
        # Quote the path when it contains chars illegal in a bare plist
        # string (e.g. the '+' in "ConfigRegistry+Builtins.swift").
        qfn = f'"{fn}"' if re.search(r"[^A-Za-z0-9_.$/:]", fn) else fn
        if not section_has(text, "PBXFileReference", fr_id):
            entry = (f"\t\t{fr_id} /* {fn} */ = {{isa = PBXFileReference; "
                     f"lastKnownFileType = {ftype}; path = {qfn}; "
                     f'sourceTree = "<group>"; }};\n')
            text = append_to_section(text, "PBXFileReference", entry)
        dir_children[dir_rel].append(f"{fr_id} /* {fn} */")
        if rel in EXCLUDE:
            continue  # file ref only; owning part re-enables the build entry
        if kind == "source":
            if not section_has(text, "PBXBuildFile", bf_id):
                entry = (f"\t\t{bf_id} /* {fn} in Sources */ = {{isa = PBXBuildFile; "
                         f"fileRef = {fr_id} /* {fn} */; }};\n")
                text = append_to_section(text, "PBXBuildFile", entry)
            phase_files.append(f"{bf_id} /* {fn} in Sources */")
        elif kind == "resource":
            if not section_has(text, "PBXBuildFile", bf_id):
                entry = (f"\t\t{bf_id} /* {fn} in Resources */ = {{isa = PBXBuildFile; "
                         f"fileRef = {fr_id} /* {fn} */; }};\n")
                text = append_to_section(text, "PBXBuildFile", entry)
            resource_files.append(f"{bf_id} /* {fn} in Resources */")

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

    # Set Sources + Resources build phase files.
    # Keep pre-existing entries the script doesn't manage
    # (e.g. Assets.xcassets, already in Resources).
    managed_bf = {uuid_for("buildfile:" + rel) for rel in files}
    text = set_array_field(text, SOURCES_PHASE_ID, "files", sorted(phase_files))
    kept = [e for e in current_phase_entries(text, RESOURCES_PHASE_ID)
            if not any(bf in e for bf in managed_bf)]
    text = set_array_field(text, RESOURCES_PHASE_ID, "files",
                           sorted(kept + resource_files))

    with open(PROJ, "w") as f:
        f.write(text)
    n_src = len(phase_files)
    n_res = len(resource_files)
    n_exc = sum(1 for rel in files if rel in EXCLUDE)
    print(f"synced {n_src} sources + {n_res} resources into project.pbxproj "
          f"({n_exc} excluded, {len(files)} files total)")


def sync_build_settings():
    """Ensure the Dudu target builds with the bridging header and the
    cppjieba header search path. Idempotent."""
    with open(PROJ) as f:
        text = f.read()

    for cfg_id in TARGET_CONFIG_IDS:
        m = re.search(
            r"(\t\t" + cfg_id + r" /\* (?:Debug|Release) \*/ = \{\n"
            r"\t\t\tisa = XCBuildConfiguration;\n"
            r"\t\t\tbuildSettings = \{\n)(.*?)(\n\t\t\};)",
            text, re.S)
        assert m, f"build configuration {cfg_id} not found"
        head, settings, tail = m.group(1), m.group(2), m.group(3)

        # SWIFT_OBJC_BRIDGING_HEADER
        if not re.search(r"^\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER =",
                         settings, re.M):
            settings += (f"\n\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "
                         f"\"{BRIDGING_HEADER}\";")

        # HEADER_SEARCH_PATHS must contain the cppjieba include dir
        hm = re.search(
            r"^\t\t\t\tHEADER_SEARCH_PATHS = \(\n(.*?)\n\t\t\t\t\);",
            settings, re.M | re.S)
        if not hm:
            settings += (
                "\n\t\t\t\tHEADER_SEARCH_PATHS = (\n"
                "\t\t\t\t\t\"$(inherited)\",\n"
                f"\t\t\t\t\t\"{CPPJIEBA_INCLUDE}\",\n"
                "\t\t\t\t);")
        elif CPPJIEBA_INCLUDE not in hm.group(1):
            new_list = hm.group(1) + f",\n\t\t\t\t\t\"{CPPJIEBA_INCLUDE}\""
            settings = (settings[:hm.start(1)] + new_list
                        + settings[hm.end(1):])

        text = text[:m.start()] + head + settings + tail + text[m.end():]

    with open(PROJ, "w") as f:
        text = f.write(text)
    print("build settings synced (bridging header + cppjieba search path)")


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
        sync_build_settings()
    else:
        sys.exit("usage: sync_pbxproj.py [--add-local-package <name> <relpath> <product>]")
