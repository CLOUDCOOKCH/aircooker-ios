import json,subprocess
raw=subprocess.check_output(['xcrun','simctl','list','devices','available','-j'],text=True)
data=json.loads(raw)
choices=[device for runtime,devices in data['devices'].items() if 'iOS-27' in runtime for device in devices if device.get('isAvailable') and 'iPhone' in device['name']]
if not choices:
    raise SystemExit('Install an iOS 27 iPhone simulator runtime; UI validation is required')
subprocess.run(['xcodebuild','-project','aircooker.xcodeproj','-scheme','aircooker','-destination','id='+choices[0]['udid'],'CODE_SIGNING_ALLOWED=NO','test'],check=True)
