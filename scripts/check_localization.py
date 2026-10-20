import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def read(locale):
    path=root/'Resources'/f'{locale}.lproj'/'Localizable.strings'
    pairs=re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");',path.read_text())
    return {json.loads(key):json.loads(value) for key,value in pairs}
en,de=read('en'),read('de')
assert en and set(en)==set(de), 'English/German key mismatch'
for key in en:
    assert en[key] and de[key],key
    assert re.findall(r'%[a-z]+',en[key])==re.findall(r'%[a-z]+',de[key]),key
for folder in ['App','ShareExtension','WidgetExtension']:
    for source in (root/folder).glob('*.swift'):
        for key in re.findall(r'String\(localized:\s*"([^"]+)"',source.read_text()):
            assert key in en,(source.name,key)
print(f'{len(en)} English/German keys and static localised errors verified.')

for reason in ['use_available_leftovers','positively_rated','library_variety','not_cooked_recently','not_planned_this_week']:
    assert 'suggestion_reason_'+reason in en,reason
