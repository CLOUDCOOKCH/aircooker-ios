"""Run real UI checks on the latest available supported iPhone runtime."""

import json
import re
import subprocess
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
subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True, timeout=180)
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
