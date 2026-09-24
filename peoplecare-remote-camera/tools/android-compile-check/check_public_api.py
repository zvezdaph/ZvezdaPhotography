#!/usr/bin/env python3
"""Checks the Android APIs referenced by the compiled app classes.

1. Public SDK: android-all (used to compile) is the full framework and also
   contains hidden APIs, so a successful compilation alone does not prove SDK
   compatibility. Every android.* class, method and field referenced by the
   bytecode is looked up in the public API signature files of Android 16
   (API 36): frameworks/base core/api/current.txt plus the mainline modules
   used by the app (Connectivity, Wi-Fi, MediaProvider).
2. minSdk: references that do not exist in the API of Android 8.0 (API 26,
   the app's minSdk) must be guarded by a Build.VERSION.SDK_INT check. The
   reviewed usages are listed, with their guard, in min_sdk_baseline.txt; any
   other newer-API reference fails the check.

Methods inherited by the app classes (e.g. startForeground() called on a
Service subclass) are resolved through the class hierarchy. Constants are
inlined by the compiler and cannot be seen in the bytecode.

Usage:
  check_public_api.py <classes-dir> --min-sdk-api <api-26.txt> --baseline <file>
                      [--classpath <jars>] <api-36-file>...
"""
import pathlib
import re
import subprocess
import sys


def split_types(text: str) -> list[str]:
    depth, token, out = 0, "", []
    for ch in text:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
        elif ch == "," and depth == 0:
            out.append(token.strip())
            token = ""
        elif depth == 0:
            token += ch
    if token.strip():
        out.append(token.strip())
    return out


PRIMITIVES = {"boolean", "byte", "char", "short", "int", "long", "float", "double"}
DESCRIPTOR_TYPES = {"Z": "boolean", "B": "byte", "C": "char", "S": "short", "I": "int", "J": "long", "F": "float", "D": "double"}


def strip_generics(text: str) -> str:
    out, depth = "", 0
    for ch in text:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
        elif depth == 0:
            out += ch
    return out


def api_params(text: str) -> tuple:
    """'@Nullable java.util.List<T>, int...' -> ('java.util.List', 'int[]'); type variables -> '*'."""
    params = []
    for raw in split_types(text):
        t = strip_generics(raw).strip()
        t = t.split(" ")[0] if " " in t else t  # drop a parameter name, if any
        dims = t.count("[]") + (1 if t.endswith("...") else 0)
        base = t.replace("[]", "").replace("...", "")
        if base not in PRIMITIVES and "." not in base:
            base = "*"  # type variable: erased to its bound in the bytecode
        params.append(base + "[]" * dims)
    return tuple(params)


def descriptor_params(descriptor: str) -> tuple:
    """'(ILandroid/app/Notification;I)V' -> ('int', 'android.app.Notification', 'int')"""
    body = descriptor[descriptor.index("(") + 1:descriptor.index(")")]
    params, i, dims = [], 0, 0
    while i < len(body):
        c = body[i]
        if c == "[":
            dims += 1
            i += 1
            continue
        if c == "L":
            end = body.index(";", i)
            name = dotted(body[i + 1:end])
            i = end + 1
        else:
            name = DESCRIPTOR_TYPES[c]
            i += 1
        params.append(name + "[]" * dims)
        dims = 0
    return tuple(params)


def params_match(api_sig: tuple, sig: tuple) -> bool:
    if len(api_sig) != len(sig):
        return False
    for a, b in zip(api_sig, sig):
        if a == b:
            continue
        a_base, b_base = a.replace("[]", ""), b.replace("[]", "")
        if a_base == "*" and a.count("[]") == b.count("[]") and b_base not in PRIMITIVES:
            continue
        return False
    return True


def parse_api(files: list[str]) -> dict[str, dict]:
    """{"android.app.Notification.Builder": {"members": {...}, "supers": [...]}}"""
    api: dict[str, dict] = {}
    for api_file in files:
        package = None
        current = None
        for line in pathlib.Path(api_file).read_text(encoding="utf-8").splitlines():
            m = re.match(r"^package ([\w.]+) \{", line)
            if m:
                package = m.group(1)
                continue
            m = re.match(
                r"^  (?:@\S+ )*public .*?(?:class|interface|enum|@interface) ([\w.]+)(?:<.*?>)?"
                r"(?: extends (.+?))?(?: implements (.+?))? \{",
                line,
            )
            if m and package:
                current = api.setdefault(f"{package}.{m.group(1)}", {"members": {}, "supers": []})
                for group in (m.group(2), m.group(3)):
                    if group:
                        current["supers"] += split_types(group)
                continue
            m = re.match(r"^    (ctor|method|field|enum_constant) (.*)", line)
            if m and current is not None:
                kind, rest = m.groups()
                # Drop annotations such as @RequiresPermission(anyOf={...}) before looking for the name.
                rest = re.sub(r"@[\w.]+(?:\((?:[^()]|\([^()]*\))*\))?\s*", "", rest)
                if kind in ("ctor", "method"):
                    n = re.search(r"([\w$]+)\((.*)\)", rest)
                    if n:
                        name = "<init>" if kind == "ctor" else n.group(1)
                        current["members"].setdefault(name, set()).add(api_params(n.group(2)))
                else:
                    n = re.search(r" ([\w$]+)(?: =|;)", rest)
                    if n:
                        current["members"].setdefault(n.group(1), set()).add(None)
            if line.startswith("  }"):
                current = None
    return api


def has_member(api: dict, cls: str, member: str, sig: tuple | None = None, seen: set | None = None) -> bool:
    """True if cls (or a supertype) declares member; for methods sig must match too."""
    seen = seen if seen is not None else set()
    if cls in seen or cls not in api:
        return False
    seen.add(cls)
    signatures = api[cls]["members"].get(member)
    if signatures is not None and (sig is None or any(a is None or params_match(a, sig) for a in signatures)):
        return True
    if member == "<init>":
        return False  # constructors are not inherited
    return any(has_member(api, s, member, sig, seen) for s in api[cls]["supers"] if not s.startswith(("java.", "javax.")))


OBJECT_MEMBERS = {"toString", "equals", "hashCode", "getClass", "wait", "notify", "notifyAll",
                  "values", "valueOf", "ordinal", "name", "compareTo", "clone", "finalize"}


# Only calls made by the app code are checked (RootEncoder has its own minSdk and guards).
OWN_PACKAGES = ("tv.peoplecare.",)


def dotted(internal: str) -> str:
    return internal.replace("/", ".").replace("$", ".")


def main() -> int:
    args = sys.argv[1:]
    classes_dir = pathlib.Path(args.pop(0))
    i = args.index("--min-sdk-api")
    min_sdk_file = args[i + 1]
    del args[i:i + 2]
    i = args.index("--baseline")
    baseline_file = args[i + 1]
    del args[i:i + 2]
    classpath = ""
    if "--classpath" in args:
        i = args.index("--classpath")
        classpath = args[i + 1]
        del args[i:i + 2]

    api = parse_api(args)
    api_min = parse_api([min_sdk_file])
    # Baseline lines: "<owner>#<member>(<params>)  -- <file>: <guard>"; '//' starts a comment line.
    baseline = {
        line.split(" -- ", 1)[0].strip()
        for line in pathlib.Path(baseline_file).read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("//")
    }

    # Declared members and supertypes of the app classes (and, through javap,
    # of library classes such as FlutterActivity) to resolve inherited calls.
    # Class names are binary names (a.b.Outer$Inner).
    classes: dict[str, dict | None] = {}
    dumps: list[str] = []

    def parse_class(out: str, name: str) -> dict:
        header = re.search(r"^[\w ]*(?:class|interface) \S+(?: extends ([^{]+?))?(?: implements ([^{]+?))?\s*\{?$", out, re.M)
        supers: list[str] = []
        if header:
            for group in header.groups():
                if group:
                    supers += [strip_generics(t).strip() for t in split_types(group)]
        declared = set(re.findall(r"^  (?:[\w$<>\[\],.? ]+ )?([\w$<>]+)\(.*\);$", out, re.M))
        declared |= set(re.findall(r"^  (?:[\w$<>\[\],.? ]+ )([\w$]+);$", out, re.M))
        # javap prints constructors with the class name.
        declared = {"<init>" if d in (name, name.split(".")[-1]) else d for d in declared}
        return {"declared": declared, "supers": [t for t in supers if t != "java.lang.Object"]}

    files = [p for p in classes_dir.rglob("*.class") if not re.match(r"^(R|BuildConfig)(\$.*)?\.class$", p.name)]
    for path in files:
        out = subprocess.run(["javap", "-v", "-p", str(path)], capture_output=True, text=True, check=True).stdout
        dumps.append(out)
        m = re.search(r"^\s*this_class: #\d+\s+// (\S+)", out, re.M)
        if m:
            name = m.group(1).replace("/", ".")
            classes[name] = parse_class(out, name)

    def class_info(name: str) -> dict | None:
        if name not in classes:
            classes[name] = None
            if classpath and not name.startswith(("android.", "java.", "javax.", "kotlin.")):
                result = subprocess.run(["javap", "-p", "-cp", classpath, name], capture_output=True, text=True)
                if result.returncode == 0:
                    classes[name] = parse_class(result.stdout, name)
        return classes[name]

    def resolve_android_owner(owner: str, member: str, sig: tuple | None, seen: set | None = None) -> str | None:
        """Returns the android.* type that provides a member called on a non-android owner."""
        seen = seen if seen is not None else set()
        if owner in seen:
            return None
        seen.add(owner)
        if owner.startswith("android."):
            return dotted(owner)
        info = class_info(owner)
        if info is None or member == "<init>" or member in info["declared"]:
            return None
        for sup in info["supers"]:
            if sup.startswith("android.") and has_member(api, dotted(sup), member, sig):
                return dotted(sup)
            found = resolve_android_owner(sup, member, sig, seen)
            if found:
                return found
        # Not found in the public API: report against the first android.* supertype.
        return next((dotted(s) for s in info["supers"] if s.startswith("android.")), None)

    not_public: set[str] = set()
    newer: set[str] = set()
    checked = 0
    for out in dumps:
        for kind, ref in re.findall(r"= (Methodref|InterfaceMethodref|Fieldref|Class)\s+\S+\s+// (\S+)", out):
            if kind == "Class":
                name = ref.strip('"').lstrip("[").lstrip("L").rstrip(";")
                if not name.startswith("android/"):
                    continue
                checked += 1
                cls = dotted(name)
                if cls not in api:
                    not_public.add(f"class {cls}")
                elif cls not in api_min:
                    newer.add(cls)
                continue
            owner_internal, _, rest = ref.partition(".")
            member, _, descriptor = rest.partition(":")
            member = member.strip('"')
            sig = descriptor_params(descriptor) if kind != "Fieldref" else None
            owner = owner_internal.replace("/", ".")
            if owner.startswith("android."):
                owner = dotted(owner)
            else:
                if not owner.startswith(OWN_PACKAGES):
                    continue
                resolved = resolve_android_owner(owner, member, sig)
                if resolved is None:
                    continue
                owner = resolved
            checked += 1
            if member in OBJECT_MEMBERS and owner in api:
                continue
            label = f"{owner}#{member}" + (f"({', '.join(sig)})" if sig is not None else "")
            if not has_member(api, owner, member, sig):
                not_public.add(label)
            elif not has_member(api_min, owner, member, sig):
                newer.add(label)

    print(f"public API: {len(files)} classes, {checked} android.* references, {len(api)} public types (API 36)")
    for problem in sorted(not_public):
        print(f"  NOT IN THE PUBLIC SDK: {problem}")
    unreviewed = sorted(n for n in newer if n not in baseline)
    print(f"minSdk 26: {len(newer)} references newer than API 26, {len(newer) - len(unreviewed)} reviewed in the baseline")
    for entry in sorted(newer):
        print(f"  {'OK (guarded)' if entry in baseline else 'NOT REVIEWED'}: {entry}")
    stale = sorted(baseline - newer)
    for entry in stale:
        print(f"  baseline entry no longer used: {entry}")
    return 1 if not_public or unreviewed else 0


if __name__ == "__main__":
    sys.exit(main())
