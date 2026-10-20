"""Check an explicit API pin and the wire fields used by the native client."""
import hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
contract=root/'Contracts'/'openapi-v1.json'
pin=json.loads((root/'Contracts'/'pin.json').read_text())
assert hashlib.sha256(contract.read_bytes()).hexdigest()==pin['sha256'], 'Contract checksum mismatch'
schema=json.loads(contract.read_text())
assert schema['info']['version']=='0.1.0'
for path in ['/api/v1/system/info','/api/v1/sync/push','/api/v1/sync/pull','/api/v1/auth/login','/api/v1/auth/refresh','/api/v1/imports']:
    assert path in schema['paths'],path
schemas=schema['components']['schemas']
expected={
'Recipe':{'title','description','source_url','source_platform','image_id','servings','ingredients','steps','notes','rating','nutrition','nutrition_source','provenance'},
'Ingredient':{'id','name','quantity','quantity_max','unit','preparation','original_text'},
'Meal':{'recipe_id','date','category','servings','order','leftover_id','recurrence','cooked'},
'Mutation':{'mutation_id','entity_id','kind','operation','base_revision','payload','device_id','client_timestamp','idempotency_key'},
'Change':{'revision','kind','entity_id','deleted','payload','updated_at'},
'Pull':{'changes','cursor','has_more'},
'Tokens':{'access_token','refresh_token','token_type','expires_in','session_id'}
}
for name,fields in expected.items():
    # FastAPI may emit separate validation/serialization schemas for decimal fields.
    candidates=[schemas[n] for n in (name,name+'-Input',name+'-Output') if n in schemas]
    assert candidates,name
    for candidate in candidates:
        assert set(candidate['properties'])==fields,(name,set(candidate['properties'])^fields)
print('Pinned OpenAPI checksum, native routes and wire field sets verified.')
