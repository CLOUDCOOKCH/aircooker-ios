"""Run real UI checks on the latest available supported iPhone runtime."""

import json
import re
import subprocess
import time
from pathlib import Path

raw = subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True
)
data = json.loads(raw)
choices = []
for runtime, devices in data["devices"].items():
    match = re.search(r"\.iOS-(\d+)(?:-(\d+))?", runtime)
    if match and int(match[1]) >= 26:
        version = (int(match[1]), int(match[2] or 0))
        for device in devices:
            if device.get("isAvailable") and "iPhone" in device["name"]:
                choices.append((version, device["name"], device["udid"], device["state"]))
if not choices:
    raise SystemExit("Install an iOS 26+ iPhone simulator runtime; UI validation is required")
version, name, udid, state = sorted(choices, reverse=True)[0]
print(f"Testing {name}, iOS {version[0]}.{version[1]}", flush=True)
if state != "Booted":
    subprocess.run(["xcrun", "simctl", "boot", udid], check=True)
# A fresh hosted runtime can spend several minutes migrating Apple system data.
# Keep a bounded deadline and visible progress without treating boot as a UI pass.
boot_started = time.monotonic()
with subprocess.Popen(["xcrun", "simctl", "bootstatus", udid, "-b"]) as boot:
    while True:
        remaining = 600 - (time.monotonic() - boot_started)
        if remaining <= 0:
            boot.kill()
            boot.wait()
            raise SystemExit("Simulator did not finish booting within 10 minutes; no UI checks ran")
        try:
            status = boot.wait(timeout=min(30, remaining))
        except subprocess.TimeoutExpired:
            print(f"Waiting for simulator readiness ({int(time.monotonic() - boot_started)}s)", flush=True)
            continue
        if status:
            raise subprocess.CalledProcessError(status, boot.args)
        break
command = [
    "xcodebuild", "-project", "aircooker.xcodeproj", "-scheme", "aircooker",
    "-derivedDataPath", "build/DerivedData",
    "-destination", "id=" + udid, "-parallel-testing-enabled", "NO",
    "CODE_SIGNING_ALLOWED=NO", "test",
]
try:
    for appearance in ["light", "dark"]:
        subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", appearance], check=True)
        bundle = f"build/NativeTests-{appearance}.xcresult"
        selected = [] if appearance == "light" else ["-only-testing:AirCookerUITests/DemoTests/testGermanDemoNavigation"]
        subprocess.run(command + ["-resultBundlePath", bundle] + selected, check=True, timeout=900)
        output = f"build/screenshots/{appearance}"
        Path(output).mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", bundle, "--output-path", output],
            check=True,
        )
finally:
    subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "light"], check=True)
