#!/usr/bin/env python3
"""Build the diagnostic APK with the workspace's verified JDK and Android tools."""
import os
import shutil
import hashlib
from pathlib import Path
import subprocess
import zipfile

project = Path(__file__).resolve().parent
workspace = project.parent.parent
tools = workspace / "work/toolchain"
jdk = next(tools.glob("jdk-*/Contents/Home"))
android = tools / "android-35/android.jar"
build_tools = tools / "android-15"
build = workspace / "work/thor-build"
build.mkdir(parents=True, exist_ok=True)
shutil.rmtree(build / "classes", ignore_errors=True)
shutil.rmtree(build / "dex", ignore_errors=True)
(build / "classes").mkdir(exist_ok=True)
(build / "dex").mkdir(exist_ok=True)
env = dict(os.environ, JAVA_HOME=str(jdk), PATH=str(jdk / "bin") + os.pathsep + os.environ.get("PATH", ""))

def run(*args):
    subprocess.run([str(a) for a in args], check=True, env=env)

for name in ("aapt2", "zipalign", "d8", "apksigner"):
    path = build_tools / name
    path.chmod(path.stat().st_mode | 0o111)

checksums=project / "third_party/SHA256SUMS"
if checksums.exists():
    for row in checksums.read_text().splitlines():
        digest,name=row.split()
        if hashlib.sha256((checksums.parent/name).read_bytes()).hexdigest()!=digest:
            raise SystemExit("Dependency checksum mismatch: "+name)
dependencies=[]
native=[]
for aar in sorted((project / "third_party").glob("*.aar")):
    with zipfile.ZipFile(aar) as z:
        jar=build / (aar.stem + ".jar")
        jar.write_bytes(z.read("classes.jar")); dependencies.append(jar)
        for name in z.namelist():
            if name.startswith("jni/arm64-v8a/") and name.endswith(".so"):
                native.append((name.replace("jni/","lib/",1),z.read(name)))
dependencies += sorted((project / "third_party").glob("*.jar"))
classpath=os.pathsep.join(map(str,[android]+dependencies))
run(jdk / "bin/javac", "--release", "8", "-classpath", classpath,
    "-d", build / "classes", *sorted(project.glob("src/**/*.java")))
run(build_tools / "d8", "--min-api", "33", "--lib", android, "--output", build / "dex", *sorted((build / "classes").rglob("*.class")), *dependencies)
run(build_tools / "aapt2", "compile", "--dir", project / "res", "-o", build / "resources.zip")
run(build_tools / "aapt2", "link", "-I", android, "--manifest", project / "AndroidManifest.xml", "--auto-add-overlay", "-R", build / "resources.zip", "-o", build / "raw.apk")
with zipfile.ZipFile(build / "raw.apk", "a", compression=zipfile.ZIP_DEFLATED) as z:
    for dex in sorted((build / "dex").glob("*.dex")):z.write(dex,dex.name)
    for name,data in native:z.writestr(name,data)
    for notice in sorted((project/"third_party").glob("LICENSE*")):z.write(notice,"assets/third-party/"+notice.name)
    z.write(project/"third_party/NOTICE.md","assets/third-party/NOTICE.md")
run(build_tools / "zipalign", "-f", "4", build / "raw.apk", build / "aligned.apk")
key = workspace / "work/thor-debug.p12"
if not key.exists():
    run(jdk / "bin/keytool", "-genkeypair", "-keystore", key, "-storetype", "PKCS12", "-storepass", "android",
        "-keypass", "android", "-alias", "androiddebugkey", "-keyalg", "RSA", "-keysize", "2048", "-validity", "3650",
        "-dname", "CN=Thor Monitor Diagnostic, O=Local Development, C=US")
apk = project.parent / "thor-monitor-test.apk"
run(build_tools / "apksigner", "sign", "--ks", key, "--ks-pass", "pass:android", "--out", apk, build / "aligned.apk")
run(build_tools / "apksigner", "verify", "--verbose", apk)
print("Built:", apk)
