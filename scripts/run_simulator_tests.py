"""Run real UI checks on the latest available supported iPhone runtime."""

import json
import re
import subprocess

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
                choices.append((version, device["name"], device["udid"]))
if not choices:
    raise SystemExit("Install an iOS 26+ iPhone simulator runtime; UI validation is required")
version, name, udid = sorted(choices, reverse=True)[0]
print(f"Testing {name}, iOS {version[0]}.{version[1]}", flush=True)
subprocess.run(
    [
        "xcodebuild", "-project", "aircooker.xcodeproj", "-scheme", "aircooker",
        "-destination", "id=" + udid, "-resultBundlePath", "build/NativeTests.xcresult",
        "CODE_SIGNING_ALLOWED=NO", "test",
    ],
    check=True,
)
