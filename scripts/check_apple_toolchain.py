"""Check actual runner capabilities rather than assuming a future Xcode release."""

import re
import subprocess

version = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
sdk = subprocess.check_output(
    ["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], text=True
).strip()
print(version)
print(f"Selected iPhoneOS SDK: {sdk}")
match = re.search(r"^Xcode (\d+)", version)
if not match or int(match[1]) < 26 or int(sdk.split(".")[0]) < 26:
    raise SystemExit("A production Xcode toolchain with iOS 26+ SDK is required")
