#!/usr/bin/env python3
"""Generates stand-ins for the aapt-generated R classes of RootEncoder
(com.pedro.encoder.R and com.pedro.library.R) from the references found in
its sources, so that they can be compiled without the Android build tools.

Usage: gen_rootencoder_r.py <rootencoder-src> <output-dir>
"""
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])


def refs(module: str, kind: str) -> list[str]:
    names: set[str] = set()
    for path in (src / module / "src" / "main" / "java").rglob("*"):
        if path.suffix in (".kt", ".java"):
            names |= set(re.findall(r"\bR\." + kind + r"\.([A-Za-z0-9_]+)", path.read_text(encoding="utf-8")))
    return sorted(names)


def write(package: str, body: str) -> None:
    target = out.joinpath(*package.split("."), "R.java")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(f"package {package};\n\n// Generated stand-in for the aapt R class.\npublic final class R {{\n{body}}}\n", encoding="utf-8")


raw = refs("encoder", "raw")
write(
    "com.pedro.encoder",
    "  public static final class raw {\n"
    + "".join(f"    public static final int {n} = {0x7F0B0000 + i};\n" for i, n in enumerate(raw))
    + "  }\n",
)
styleable = refs("library", "styleable")
write(
    "com.pedro.library",
    "  public static final class styleable {\n"
    + "".join(
        f"    public static final int {n} = {i};\n" if "_" in n else f"    public static final int[] {n} = new int[0];\n"
        for i, n in enumerate(styleable)
    )
    + "  }\n",
)
print(f"R stubs: {len(raw)} raw resources, {len(styleable)} styleable entries")
