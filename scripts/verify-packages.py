#!/usr/bin/env python3
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def verify(package, scheme, injection_path=None):
    control = pathlib.Path(__file__).resolve().parents[1] / "control"
    expected_version = next(line.removeprefix("Version: ") for line in control.read_text().splitlines()
                            if line.startswith("Version: "))
    expected_name = "com.wcsy.reply.roothide" if scheme == "roothide" else "com.wcsy.reply"
    expected_arch = "iphoneos-arm64e" if scheme == "roothide" else "iphoneos-arm64"
    assert run("dpkg-deb", "-f", package, "Package") == expected_name
    assert run("dpkg-deb", "-f", package, "Architecture") == expected_arch
    assert run("dpkg-deb", "-f", package, "Version") == expected_version
    with tempfile.TemporaryDirectory() as temp:
        subprocess.check_call(["dpkg-deb", "-x", package, temp])
        prefix = "" if scheme == "roothide" else "var/jb/"
        base = pathlib.Path(temp) / prefix / "Library/MobileSubstrate/DynamicLibraries"
        dylib = base / "WcSy.dylib"
        filter_file = base / "WcSy.plist"
        assert dylib.is_file() and filter_file.is_file()
        payload = {p.relative_to(temp).as_posix() for p in pathlib.Path(temp).rglob("*") if p.is_file()}
        assert payload == {str(dylib.relative_to(temp)), str(filter_file.relative_to(temp))}
        assert plistlib.loads(filter_file.read_bytes())["Filter"]["Bundles"] == ["com.tencent.xin"]
        assert set(run("lipo", "-archs", str(dylib)).split()) == {"arm64", "arm64e"}
        load_commands = run("otool", "-l", str(dylib))
        if scheme == "roothide":
            assert load_commands.count("LC_RPATH") >= 2
            assert "@loader_path/.jbroot/Library/Frameworks" in load_commands
            assert "@loader_path/.jbroot/usr/lib" in load_commands
        assert re.search(r"cmd LC_LOAD_WEAK_DYLIB\s+cmdsize \d+\s+name @rpath/CydiaSubstrate\.framework/CydiaSubstrate", load_commands)
        symbols = run("nm", str(dylib))
        assert "_logosLocalInit" not in symbols
        dylib_bytes = dylib.read_bytes()
        for marker in ("com.tencent.xin", "BaseMsgContentViewController", "GetMessagesWrapArray",
                       "getInputToolView", "setText:", "WCPluginsMgr", "RCSettingsViewController"):
            assert marker.encode() in dylib_bytes or marker.encode("utf-16-le") in dylib_bytes
        if injection_path:
            # Export the checked payload, not an unverified intermediate object.
            subprocess.check_call(["lipo", str(dylib), "-thin", "arm64", "-output", injection_path])
            assert run("lipo", "-archs", injection_path) == "arm64"
            assert pathlib.Path(injection_path).read_bytes() == subprocess.check_output(
                ["lipo", str(dylib), "-thin", "arm64", "-output", "/dev/stdout"])
    print(f"verified {scheme}: {package}")


if __name__ == "__main__":
    assert len(sys.argv) in (3, 4), "usage: verify-packages.py ROOTLESS_DEB ROOTHIDE_DEB [INJECTION_DYLIB]"
    verify(sys.argv[1], "rootless")
    verify(sys.argv[2], "roothide", sys.argv[3] if len(sys.argv) == 4 else None)
