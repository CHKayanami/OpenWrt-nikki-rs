"""Run with native apk/usign/po2lmo on PATH for the full integration checks."""

import gzip
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "packaging_tools", Path(__file__).resolve().parents[1] / "scripts/packaging/pack.py")
pack = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = pack
SPEC.loader.exec_module(pack)


def tar_contents(data):
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        return {m.name.removeprefix("./"): (archive.extractfile(m).read(), m)
                for m in archive if m.isfile()}


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.payload = self.root / "payload"
        pack.write(self.payload / "etc/config/nikki-rs", "config config 'config'\n", 0o600)
        pack.write(self.payload / "etc/init.d/nikki-rs", "#!/bin/sh\nexit 0\n", 0o755)
        self.package = pack.Package("nikki-rs", "1.0.6-r2", self.payload, "Test package",
                                    ["libc", "clash-rs"], ["/etc/config/nikki-rs"],
                                    {"postrm": "#!/bin/sh\ntrue\n"})
        self.output = self.root / "output"
        self.output.mkdir()

    def test_existing_matrix_is_preserved(self):
        count = sum(len(pack.TARGETS["architectures"]) - len(branch["exclude"])
                    for branch in pack.TARGETS["branches"].values())
        self.assertEqual(count, 42)
        self.assertEqual(len(set(pack.TARGETS["architectures"].values())), 5)

    def test_ipk_payload_reused_with_real_architecture_and_lifecycle(self):
        archives = []
        for arch in ["x86_64", "aarch64_cortex-a53"]:
            path, metadata = pack.package_ipk(self.package, arch, self.output)
            self.assertEqual(path.name, f"nikki-rs_1.0.6-r2_{arch}.ipk")
            self.assertEqual(metadata["Architecture"], arch)
            outer = tar_contents(path.read_bytes())
            self.assertEqual(outer["debian-binary"][0], b"2.0\n")
            archives.append(outer["data.tar.gz"][0])
            control = tar_contents(outer["control.tar.gz"][0])
            self.assertIn(f"Architecture: {arch}\n".encode(), control["control"][0])
            self.assertIn(b'default_postinst "$0" "$@"', control["postinst"][0])
            self.assertIn(b'default_prerm "$0" "$@"', control["prerm"][0])
            self.assertEqual(control["postrm"][0], self.package.scripts["postrm"].encode())
            self.assertEqual(control["conffiles"][0], b"/etc/config/nikki-rs\n")
            data = tar_contents(outer["data.tar.gz"][0])
            self.assertEqual(data["etc/config/nikki-rs"][1].mode, 0o600)
            self.assertEqual(data["etc/init.d/nikki-rs"][1].mode, 0o755)
            self.assertEqual(data["etc/init.d/nikki-rs"][1].uid, 0)
        self.assertEqual(*archives)

    def test_luci_stays_universal_and_ipk_is_reproducible(self):
        self.package.name = "luci-app-nikki-rs"
        self.package.universal = True
        first, _ = pack.package_ipk(self.package, "x86_64", self.output)
        data = first.read_bytes()
        second, _ = pack.package_ipk(self.package, "aarch64_cortex-a53", self.output)
        self.assertTrue(second.name.endswith("_all.ipk"))
        self.assertEqual(data, second.read_bytes())

    def test_metadata_comes_from_current_makefile(self):
        metadata = pack.make_metadata("nikki-rs", self.payload)
        self.assertIn("clash-rs", metadata.depends)
        self.assertIn("firewall4", metadata.depends)
        self.assertIn("/etc/config/nikki-rs", metadata.conffiles)
        self.assertIn("commit firewall", metadata.scripts["postrm"])
        self.assertNotIn("$$", metadata.scripts["postrm"])

    def test_apk_upgrade_sets_upgrade_flag_before_install_logic(self):
        self.package.scripts["postinst-pkg"] = "#!/bin/sh\necho luci-refresh\n"
        scripts = pack.lifecycle(self.package, apk=True)
        self.assertLess(scripts["post-upgrade"].index("export PKG_UPGRADE=1"),
                        scripts["post-upgrade"].index("default_postinst"))
        self.assertIn('export pkgname="nikki-rs"', scripts["pre-deinstall"])
        self.assertIn("echo luci-refresh", scripts["post-install"])
        self.assertEqual(scripts["post-deinstall"], self.package.scripts["postrm"])

    @unittest.skipUnless(shutil.which("apk"), "native apk tool is required")
    def test_real_apk_architecture_scripts_index_and_config_checksums(self):
        for arch in ["x86_64", "aarch64_cortex-a53"]:
            destination = self.output / arch
            destination.mkdir()
            path = pack.package_apk(self.package, arch, destination, self.root / arch)
            dump = subprocess.check_output(["apk", "adbdump", "--format", "json", str(path)], text=True)
            self.assertIn(arch, dump)
            self.assertIn("post-upgrade", dump)
            self.assertIn("PKG_UPGRADE", dump)
            def check_ownership(value):
                if isinstance(value, dict):
                    if "acl" in value:
                        self.assertEqual(value["acl"].get("user", "root"), "root")
                        self.assertEqual(value["acl"].get("group", "root"), "root")
                        self.assertNotIn("xattrs", value["acl"])
                    for child in value.values():
                        check_ownership(child)
                elif isinstance(value, list):
                    for child in value:
                        check_ownership(child)
            check_ownership(json.loads(dump))
            extracted = self.root / f"extract-{arch}"
            extracted.mkdir()
            pack.run("apk", "extract", "--allow-untrusted", "--no-chown", "--destination", extracted, path)
            expected = pack.sha256(self.payload / "etc/config/nikki-rs")
            self.assertEqual((extracted / "lib/apk/packages/nikki-rs.conffiles_static").read_text(),
                             f"/etc/config/nikki-rs {expected}\n")
            self.assertEqual((extracted / "etc/config/nikki-rs").stat().st_mode & 0o777, 0o600)
            index = destination / "packages.adb"
            pack.run("apk", "mkndx", "--allow-untrusted", "--output", index, path)
            self.assertGreater(index.stat().st_size, 0)

    @unittest.skipUnless(shutil.which("apk") and shutil.which("openssl"), "apk and openssl required")
    def test_apk_package_and_index_signatures(self):
        key = self.root / "private.pem"
        pack.run("openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
                 "-out", key, stderr=subprocess.DEVNULL)
        keys = self.root / "keys"
        keys.mkdir()
        pack.run("openssl", "pkey", "-in", key, "-pubout", "-out", keys / "test.pem", stderr=subprocess.DEVNULL)
        path = pack.package_apk(self.package, "x86_64", self.output, self.root / "signed", key)
        pack.run("apk", "verify", "--keys-dir", keys, path)
        index = self.output / "packages.adb"
        pack.run("apk", "mkndx", "--keys-dir", keys, "--sign-key", key, "--output", index, path)
        pack.run("apk", "verify", "--keys-dir", keys, index)

    @unittest.skipUnless(shutil.which("usign"), "usign required")
    def test_ipk_index_signature(self):
        private = self.root / "private"
        public = self.root / "public"
        pack.run("usign", "-G", "-s", private, "-p", public)
        path, _ = pack.package_ipk(self.package, "x86_64", self.output)
        index = self.output / "Packages"
        pack.write(index, f"Filename: {path.name}\nSHA256sum: {pack.sha256(path)}\n")
        signature = self.output / "Packages.sig"
        pack.run("usign", "-S", "-m", index, "-s", private, "-x", signature)
        pack.run("usign", "-V", "-m", index, "-p", public, "-x", signature)

    @unittest.skipUnless(shutil.which("apk") and shutil.which("fakeroot"), "apk and fakeroot required")
    def test_apk_upgrade_preserves_modified_configuration(self):
        # Both transactions are confined to an empty root, with scripts/network
        # disabled. No package is installed in the build host's own database.
        self.package.depends = []
        self.package.version = "1.0.6-r1"
        old = pack.package_apk(self.package, "x86_64", self.output, self.root / "old")
        install_root = self.root / "install-root"
        install_root.mkdir()
        args = ["fakeroot", "--", "apk", "--root", install_root, "--arch", "x86_64",
                "--initdb", "--no-network", "--no-scripts", "--allow-untrusted",
                "--force-non-repository", "add"]
        pack.run(*args, old)
        config = install_root / "etc/config/nikki-rs"
        config.write_text("user-modified configuration\n")
        pack.write(self.payload / "etc/config/nikki-rs", "new default configuration\n", 0o600)
        self.package.version = "1.0.6-r2"
        new = pack.package_apk(self.package, "x86_64", self.output, self.root / "new")
        pack.run(*args, new)
        self.assertEqual(config.read_text(), "user-modified configuration\n")


if __name__ == "__main__":
    unittest.main()
