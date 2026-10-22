#!/usr/bin/env python3
"""Prepare payloads once, then package for each existing OpenWrt feed architecture.

IPK layout and APK lifecycle wrappers follow OpenWrt include/package-pack.mk.
The application Makefiles remain the source of versions, dependencies, installed
backend files, configuration preservation and package-specific uninstall scripts.
"""

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
import gzip
from functools import lru_cache
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TARGETS = json.loads((Path(__file__).with_name("targets.json")).read_text())


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def variable(text, name, default=None):
    match = re.search(r"^\s*" + re.escape(name) + r"\s*:?=\s*(.+)$", text, re.M)
    if match:
        return match[1].strip()
    if default is not None:
        return default
    raise ValueError(f"Missing Makefile variable {name}")


def block(text, name):
    match = re.search(r"^define " + re.escape(name) + r"\n(.*?)^endef", text, re.M | re.S)
    if not match:
        raise ValueError(f"Missing Makefile definition {name}")
    return match[1]


def write(path, text, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


@dataclass
class Package:
    name: str
    version: str
    payload: Path
    description: str
    depends: list = field(default_factory=list)
    conffiles: list = field(default_factory=list)
    scripts: dict = field(default_factory=dict)
    universal: bool = False
    license: str = "GPL-3.0-or-later"
    url: str = "https://github.com/CHKayanami/OpenWrt-nikki-rs"
    section: str = "net"


def make_metadata(name, payload):
    text = (ROOT / name / "Makefile").read_text()
    definition = block(text, f"Package/{name}")
    package = Package(
        name, variable(text, "PKG_VERSION") + "-r" + variable(text, "PKG_RELEASE", "1"),
        payload, variable(definition, "TITLE"),
        [dep.lstrip("+") for dep in variable(definition, "DEPENDS", "").split()],
        license=variable(text, "PKG_LICENSE", "GPL-3.0-or-later"),
        url=variable(definition, "URL"),
    )
    if re.search(r"^define Package/" + re.escape(name) + r"/conffiles$", text, re.M):
        package.conffiles = block(text, f"Package/{name}/conffiles").split()
    if re.search(r"^define Package/" + re.escape(name) + r"/postrm$", text, re.M):
        package.scripts["postrm"] = block(text, f"Package/{name}/postrm").replace("$$", "$")
    return package


def translation_version():
    revision = subprocess.check_output(
        ["git", "log", "-1", "--format=%ct %h", "--abbrev=7", "--", "luci-app-nikki-rs/po"],
        cwd=ROOT, text=True,
    ).strip()
    if not revision:
        raise ValueError("Translation history is required; checkout with fetch-depth: 0")
    stamp, commit = revision.split()
    stamp = int(stamp)
    date = datetime.fromtimestamp(stamp, timezone.utc)
    return f"{date:%y.%j}.{stamp % 86400:05d}~{commit}"


def prepare(work, cache):
    if (work / "manifest.json").exists():
        raise ValueError(f"Use a fresh preparation directory: {work}")
    work.mkdir(parents=True, exist_ok=True)
    backend = work / "payloads/nikki-rs"
    backend.mkdir(parents=True)
    text = (ROOT / "nikki-rs/Makefile").read_text()
    # Execute the existing install recipe without including SDK build machinery.
    recipe = block(text, "Package/nikki-rs/install")
    recipe = recipe.replace("$(CURDIR)", str(ROOT / "nikki-rs")).replace("$(1)", str(backend))
    makefile = "INSTALL_DIR := install -d -m0755\nINSTALL_BIN := install -m0755\n"
    makefile += "INSTALL_DATA := install -m0644\nINSTALL_CONF := install -m0600\nstage:\n" + recipe
    run("make", "-f", "-", "stage", input=makefile, text=True, stdout=subprocess.DEVNULL)
    packages = [make_metadata("nikki-rs", backend)]

    luci = ROOT / "luci-app-nikki-rs"
    payload = work / "payloads/luci-app-nikki-rs"
    shutil.copytree(luci / "htdocs", payload / "www")
    shutil.copytree(luci / "root", payload, dirs_exist_ok=True)
    version = variable((luci / "Makefile").read_text(), "PKG_VERSION") + "-r1"
    # Equivalent to luci.mk's postinst-pkg. JS source is shipped unminified.
    postinst = ('#!/bin/sh\n[ -n "${IPKG_INSTROOT}" ] || {\n'
                '\trm -f /tmp/luci-indexcache.*\n\trm -rf /tmp/luci-modulecache/\n'
                '\t/etc/init.d/rpcd reload 2>/dev/null\n\texit 0\n}\n')
    packages.append(Package("luci-app-nikki-rs", version, payload, "LuCI Support for nikki-rs",
                            ["libc", "luci-base", "nikki-rs"], scripts={"postinst-pkg": postinst},
                            universal=True, section="luci"))
    po_version = translation_version()
    languages = {"zh_Hans": "zh-cn", "zh_Hant": "zh-tw"}
    for directory in sorted((luci / "po").iterdir()):
        if directory.name == "templates" or not directory.is_dir():
            continue
        lang = languages.get(directory.name, directory.name)
        name = "luci-i18n-nikki-rs-" + lang
        payload = work / "payloads" / name
        destination = payload / "usr/lib/lua/luci/i18n"
        destination.mkdir(parents=True)
        for po in sorted(directory.glob("*.po")):
            run("po2lmo", po, destination / f"{po.stem}.{lang}.lmo")
        write(payload / "etc/uci-defaults" / name,
              f"uci set luci.languages.{lang.replace('-', '_')}='{lang}'; uci commit luci\n")
        packages.append(Package(name, po_version, payload, f"Translation for nikki-rs - {lang}",
                                ["libc", "luci-app-nikki-rs"], universal=True, section="luci"))

    core_text = (ROOT / "clash-rs/Makefile").read_text()
    hashes = dict(re.findall(r"CLASH_TARGET:=([^\s]+)\s+CLASH_HASH:=([a-f0-9]{64})", core_text))
    base_url = variable(core_text, "PKG_SOURCE_URL").rstrip("/")
    core_packages = {}
    for target in sorted(set(TARGETS["architectures"].values())):
        expected_hash = hashes[target]
        archive_name = f"clash-rs-minimal-{target}.tar.gz"
        archive = cache / expected_hash / archive_name
        archive.parent.mkdir(parents=True, exist_ok=True)
        if not archive.exists() or sha256(archive) != expected_hash:
            temporary = archive.with_suffix(".part")
            run("curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error",
                base_url + "/" + archive_name, "--output", temporary)
            if sha256(temporary) != expected_hash:
                temporary.unlink()
                raise ValueError(f"Core checksum mismatch: {target}")
            temporary.replace(archive)
        payload = work / "cores" / target
        binary = payload / "usr/bin/clash-rs"
        binary.parent.mkdir(parents=True)
        with tarfile.open(archive) as tar:
            members = [m for m in tar if m.isfile() and Path(m.name).name == "clash-rs"]
            if len(members) != 1:
                raise ValueError(f"Expected one clash-rs binary in {archive}")
            with tar.extractfile(members[0]) as stream, binary.open("wb") as output:
                shutil.copyfileobj(stream, output)
        binary.chmod(0o755)
        core_packages[target] = make_metadata("clash-rs", payload)
    # SDK package defaults add libc even for these script-only packages.
    packages[0].depends.insert(0, "libc")
    for package in core_packages.values():
        package.depends.insert(0, "libc")
    manifest = {"packages": [], "cores": {}}
    for package in packages + list(core_packages.values()):
        package.payload = str(package.payload.relative_to(work))
    manifest["packages"] = [vars(p) for p in packages]
    manifest["cores"] = {target: vars(p) for target, p in core_packages.items()}
    write(work / "manifest.json", json.dumps(manifest, indent=2) + "\n")


def archive_bytes(files, epoch=0):
    """Deterministic gzip/tar, with root ownership independent of the runner."""
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", mtime=epoch, filename="") as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.GNU_FORMAT) as tar:
            for name, content, mode in sorted(files):
                info = tarfile.TarInfo("./" + name)
                info.uid = info.gid = 0
                info.mode = mode
                info.mtime = epoch
                if content is None:
                    info.type = tarfile.DIRTYPE
                    tar.addfile(info)
                else:
                    info.size = len(content)
                    tar.addfile(info, io.BytesIO(content))
    return output.getvalue()


def payload_entries(root):
    return [(p.relative_to(root).as_posix(), None if p.is_dir() else p.read_bytes(),
             p.stat().st_mode & 0o777) for p in sorted(root.rglob("*"))]


@lru_cache(maxsize=16)
def payload_archive(root):
    return archive_bytes(payload_entries(root))


def lifecycle(package, apk=False):
    guard = '[ -s "${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0\n. "${IPKG_INSTROOT}/lib/functions.sh"\n'
    post = '[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0\n' + guard
    if not apk:
        return {"postinst": "#!/bin/sh\n" + post + 'default_postinst "$0" "$@"\n',
                "prerm": "#!/bin/sh\n" + guard + 'default_prerm "$0" "$@"\n', **package.scripts}
    exports = f'export root="${{IPKG_INSTROOT}}"\nexport pkgname="{package.name}"\n'
    custom = package.scripts.get("postinst-pkg", "")
    custom = "\n".join(line for line in custom.splitlines() if not line.startswith("#!"))
    install = post + exports + "add_group_and_user\ndefault_postinst\n" + custom + "\n"
    result = {"post-install": "#!/bin/sh\n" + install,
              "post-upgrade": "#!/bin/sh\nexport PKG_UPGRADE=1\n" + install,
              "pre-deinstall": "#!/bin/sh\n" + guard + exports + "default_prerm\n"}
    if "postrm" in package.scripts:
        result["post-deinstall"] = package.scripts["postrm"]
    return result


def package_ipk(package, arch, destination):
    arch = "all" if package.universal else arch
    data = payload_archive(package.payload)
    control = {"Package": package.name, "Version": package.version,
               "Depends": ", ".join(package.depends), "SourceName": package.name,
               "License": package.license, "Section": package.section,
               "URL": package.url, "Architecture": arch,
               "Installed-Size": str(len(gzip.decompress(data))), "Description": package.description}
    metadata = [("control", "".join(f"{k}: {v}\n" for k, v in control.items() if v).encode(), 0o644)]
    metadata += [(name, body.encode(), 0o755) for name, body in lifecycle(package).items()]
    if package.conffiles:
        metadata.append(("conffiles", ("\n".join(package.conffiles) + "\n").encode(), 0o644))
    # OpenWrt IPKs use a gzipped outer tar, not a Debian ar archive.
    path = destination / f"{package.name}_{package.version}_{arch}.ipk"
    path.write_bytes(archive_bytes([("debian-binary", b"2.0\n", 0o644),
                                  ("data.tar.gz", data, 0o644),
                                  ("control.tar.gz", archive_bytes(metadata), 0o644)]))
    return path, control


def package_apk(package, arch, destination, scratch, key=None):
    arch = "noarch" if package.universal else arch
    root = scratch / package.name
    shutil.copytree(package.payload, root)
    info = root / "lib/apk/packages"
    info.mkdir(parents=True, exist_ok=True)
    listing = sorted("/" + p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())
    write(info / f"{package.name}.list", "\n".join(listing) + "\n")
    if package.conffiles:
        write(info / f"{package.name}.conffiles", "\n".join(package.conffiles) + "\n")
        checksums = [f"{p} {sha256(root / p.lstrip('/'))}" for p in package.conffiles]
        write(info / f"{package.name}.conffiles_static", "\n".join(checksums) + "\n")
    args = ["apk", "mkpkg", "--no-xattrs", "--info", f"name:{package.name}",
            "--info", f"version:{package.version}", "--info", f"arch:{arch}",
            "--info", f"description:{package.description}", "--info", f"license:{package.license}",
            "--info", f"url:{package.url}", "--info", f"depends:{' '.join(package.depends)}"]
    for name, body in lifecycle(package, apk=True).items():
        script = scratch / f"{package.name}.{name}"
        write(script, body, 0o755)
        args += ["--script", f"{name}:{script}"]
    if key:
        args += ["--sign-key", key]
    path = destination / f"{package.name}-{package.version}.apk"
    # Set archive ownership without requiring a privileged runner. Keep chown and
    # mkpkg in the same fakeroot session so its virtual ownership reaches APK.
    run("fakeroot", "--", "sh", "-c", 'chown -R 0:0 "$1" || exit 1; shift; exec "$@"',
        "package-apk", root, *args, "--files", root, "--output", path,
        env={**os.environ, "SOURCE_DATE_EPOCH": "0"})
    return path


def build(work, output, branch, arch_filter=None, sign=False):
    manifest = json.loads((work / "manifest.json").read_text())
    packages = [Package(**entry) for entry in manifest["packages"]]
    cores = {target: Package(**entry) for target, entry in manifest["cores"].items()}
    for package in packages + list(cores.values()):
        package.payload = work / package.payload
    config = TARGETS["branches"][branch]
    key_name = "KEY_BUILD" if config["format"] == "ipk" else "PRIVATE_KEY"
    key_text = os.environ.get(key_name, "")
    if sign and not key_text:
        raise ValueError(f"Signing requested, but {key_name} is empty")
    # Build universal packages once for this format/branch, then copy exact bytes.
    with tempfile.TemporaryDirectory(prefix="nikki-pack-") as temporary:
        scratch = Path(temporary)
        key = scratch / "signing-key"
        if sign:
            write(key, key_text, 0o600)
        universal_dir = scratch / "universal"
        universal_dir.mkdir()
        universal_ipk = {}
        for package in packages:
            if not package.universal:
                continue
            if config["format"] == "ipk":
                universal_ipk[package.name] = package_ipk(package, "all", universal_dir)
            else:
                package_apk(package, "noarch", universal_dir, scratch / "universal-stage", key if sign else None)
        for arch, target in TARGETS["architectures"].items():
            if arch in config["exclude"] or (arch_filter and arch not in arch_filter):
                continue
            feed = output / "public" / branch / arch / "nikki_rs"
            feed.mkdir(parents=True, exist_ok=False)
            records = []
            versions = {}
            with tempfile.TemporaryDirectory(dir=scratch) as staging:
                for package in [cores[target], *packages]:
                    versions[package.name] = package.version
                    if config["format"] == "ipk":
                        if package.universal:
                            original, metadata = universal_ipk[package.name]
                            path = feed / original.name
                            shutil.copyfile(original, path)
                        else:
                            path, metadata = package_ipk(package, arch, feed)
                        record = dict(metadata, Filename=path.name, Size=str(path.stat().st_size), SHA256sum=sha256(path))
                        records.append("".join(f"{k}: {v}\n" for k, v in record.items() if v))
                    elif package.universal:
                        filename = f"{package.name}-{package.version}.apk"
                        shutil.copyfile(universal_dir / filename, feed / filename)
                    else:
                        package_apk(package, arch, feed, Path(staging), key if sign else None)
            write(feed / "index.json", json.dumps({"packages": versions}, sort_keys=True) + "\n")
            if config["format"] == "ipk":
                write(feed / "Packages", "\n".join(records) + "\n")
                with gzip.GzipFile(filename=str(feed / "Packages.gz"), mode="wb", mtime=0) as gz:
                    gz.write((feed / "Packages").read_bytes())
                if sign:
                    run("usign", "-S", "-m", feed / "Packages", "-s", key, "-x", feed / "Packages.sig")
            else:
                args = ["apk", "mkndx", "--allow-untrusted", "--output", feed / "packages.adb"]
                if sign:
                    args += ["--sign-key", key]
                run(*args, *sorted(feed.glob("*.apk")))
            release = output / "release"
            release.mkdir(exist_ok=True)
            with tarfile.open(release / f"nikki-rs_{arch}-{branch}.tar.gz", "w:gz") as tar:
                for path in sorted(feed.iterdir()):
                    tar.add(path, arcname="./" + path.name)
            print(f"Packaged {branch}/{arch}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "build"])
    parser.add_argument("--work", type=Path, default=Path(".package-work"))
    parser.add_argument("--cache", type=Path, default=Path(".package-cache"))
    parser.add_argument("--output", type=Path, default=Path(".package-output"))
    parser.add_argument("--branch", choices=list(TARGETS["branches"]))
    parser.add_argument("--arch", action="append", choices=list(TARGETS["architectures"]))
    parser.add_argument("--sign", action="store_true")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.work.resolve(), args.cache.resolve())
    else:
        if not args.branch:
            parser.error("build requires --branch")
        build(args.work.resolve(), args.output.resolve(), args.branch, args.arch, args.sign)


if __name__ == "__main__":
    main()
