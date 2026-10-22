"""Install operator-provided CI signing material without logging secrets.
Profiles are a base64 JSON object mapping UUID.mobileprovision names to base64 data.
Run only in an isolated protected macOS runner.
"""
import base64,json,os,re,subprocess,sys
from pathlib import Path
os.umask(0o077)
root=Path(os.environ['RUNNER_TEMP'])/'mealf-signing'
keychain=root/'temporary.keychain-db'
profile_root=Path.home()/'Library'/'MobileDevice'/'Provisioning Profiles'
api_root=Path.home()/'private_keys'
if '--cleanup' in sys.argv:
    if keychain.exists():
        subprocess.run(['security','delete-keychain',str(keychain)],check=False,stdout=subprocess.DEVNULL)
    manifest=root/'files.json'
    if manifest.exists():
        for name in json.loads(manifest.read_text()):Path(name).unlink(missing_ok=True)
    import shutil
    shutil.rmtree(root,ignore_errors=True)
    raise SystemExit(0)
root.mkdir(mode=0o700,exist_ok=True)
required=['SIGNING_P12_BASE64','SIGNING_P12_PASSWORD','SIGNING_PROFILES_BASE64','ASC_KEY_BASE64','ASC_KEY_ID','TEMP_KEYCHAIN_PASSWORD']
if any(not os.environ.get(key) for key in required):raise SystemExit('Missing protected signing configuration')
if not re.fullmatch(r'[A-Za-z0-9]+',os.environ['ASC_KEY_ID']):raise SystemExit('Invalid ASC key ID')
certificate=root/'certificate.p12';certificate.write_bytes(base64.b64decode(os.environ['SIGNING_P12_BASE64'],validate=True));certificate.chmod(0o600)
password=os.environ['TEMP_KEYCHAIN_PASSWORD']
commands=[['security','create-keychain','-p',password,str(keychain)],['security','set-keychain-settings','-lut','21600',str(keychain)],['security','unlock-keychain','-p',password,str(keychain)],['security','import',str(certificate),'-P',os.environ['SIGNING_P12_PASSWORD'],'-T','/usr/bin/codesign','-T','/usr/bin/security','-t','cert','-f','pkcs12','-k',str(keychain)],['security','set-key-partition-list','-S','apple-tool:,apple:','-k',password,str(keychain)],['security','list-keychains','-d','user','-s',str(keychain)]]
for command in commands:
    result=subprocess.run(command,check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if result.returncode:raise SystemExit('Signing setup failed; command details suppressed to protect credentials')
profile_root.mkdir(parents=True,exist_ok=True);api_root.mkdir(parents=True,exist_ok=True)
created=[]
for filename,encoded in json.loads(base64.b64decode(os.environ['SIGNING_PROFILES_BASE64'],validate=True)).items():
    if not re.fullmatch(r'[A-Fa-f0-9-]+\.mobileprovision',filename):raise SystemExit('Invalid profile filename')
    target=profile_root/filename;target.write_bytes(base64.b64decode(encoded,validate=True));target.chmod(0o600);created.append(str(target))
key=api_root/('AuthKey_'+os.environ['ASC_KEY_ID']+'.p8');key.write_bytes(base64.b64decode(os.environ['ASC_KEY_BASE64'],validate=True));key.chmod(0o600);created.append(str(key))
(root/'files.json').write_text(json.dumps(created))
