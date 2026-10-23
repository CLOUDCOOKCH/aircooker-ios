"""Check an explicit API pin and the wire fields used by the native client."""
import hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
contract=root/'Contracts'/'openapi-v1.json'
pin=json.loads((root/'Contracts'/'pin.json').read_text())
assert hashlib.sha256(contract.read_bytes()).hexdigest()==pin['sha256'], 'Contract checksum mismatch'
schema=json.loads(contract.read_text())
assert schema['info']['version']=='0.1.0'
for path in ['/api/v1/system/info','/api/v1/sync/push','/api/v1/sync/pull','/api/v1/auth/login','/api/v1/auth/refresh','/api/v1/auth/revoke','/api/v1/imports','/api/v1/media/{image_id}','/api/v1/media/{image_id}/info','/api/v1/suggestions/weekly','/api/v1/suggestions/apply','/api/v1/admin/ai','/api/v1/admin/ai/test','/api/v1/admin/status','/api/v1/sync/state','/api/v1/sync/snapshot']:
    assert path in schema['paths'],path
schemas=schema['components']['schemas']
expected={
'Refresh':{'refresh_token'},
'SyncAnchor':{'cursor','token'},
'SyncState':{'instance_id','cursor','token','requested_cursor','requested_token'},
'SyncSnapshot':{'instance_id','checkpoint','changes','next_after'},
'Push':{'mutations','checkpoint'},
'MutationResult':{'mutation_id','status','revision','conflict','revision_token'},
'SessionInfo':{'id','device_id','access_expires','refresh_expires','revoked','current'},
'AdministrationStatus':{'database_bytes','media_bytes','disk_free_bytes','pending_jobs','recipes'},
'Leftover':{'recipe_id','portions','produced_on','discarded'},
'SuggestionPreview':{'preview','monday','basis','meals'},
'SuggestionApply':{'request_id','monday','basis','mutations','checkpoint'},
'MediaInfo':{'id','content_type','sha256','byte_count','width','height','created_at'},
'Recurrence':{'interval_weeks','until','exceptions'},
'Template':{'name','meals'},
'TemplateSlot':{'weekday','category','recipe_id','servings'},
'Recipe':{'title','description','source_url','source_platform','image_id','servings','ingredients','steps','notes','rating','nutrition','nutrition_source','provenance','schema_version','instruction_details','times','language','yield_info','category','cuisine','tags'},
'Ingredient':{'id','name','quantity','quantity_max','unit','preparation','original_text','quantity_text','notes','optional','group'},
'Meal':{'recipe_id','date','category','servings','order','leftover_id','recurrence','cooked'},
'Mutation':{'mutation_id','entity_id','kind','operation','base_revision','payload','device_id','client_timestamp','idempotency_key'},
'Change':{'revision','kind','entity_id','deleted','payload','updated_at'},
'Pull':{'changes','cursor','has_more','cursor_token'},
'Tokens':{'access_token','refresh_token','token_type','expires_in','session_id'}
}
for name,fields in expected.items():
    # FastAPI may emit separate validation/serialization schemas for decimal fields.
    candidates=[schemas[n] for n in (name,name+'-Input',name+'-Output') if n in schemas]
    assert candidates,name
    for candidate in candidates:
        assert set(candidate['properties'])==fields,(name,set(candidate['properties'])^fields)
print('Pinned OpenAPI checksum, native routes and wire field sets verified.')

fixture=root/'Tests'/'MealfCoreTests'/'Fixtures'/'recommendations-v1.json'
assert hashlib.sha256(fixture.read_bytes()).hexdigest()==pin['fixtures']['recommendations-v1']['sha256'], 'Recommendation fixture pin mismatch'

history=root/"Tests"/"MealfCoreTests"/"Fixtures"/"sync-history-v1.json"
assert hashlib.sha256(history.read_bytes()).hexdigest()==pin["fixtures"]["sync-history-v1"]["sha256"], "History fixture pin mismatch"
assert json.loads(history.read_text())["format_version"]==1

revocation=schema["paths"]["/api/v1/auth/revoke"]["post"]
assert "204" in revocation["responses"]
assert revocation["requestBody"]["content"]["application/json"]["schema"]["$ref"].endswith("/Refresh")

# Reviewed additive fields remain optional for the retained native v1 client.
for name, field in [("ImportRequest", "image_id"), ("SuggestionApply", "checkpoint"), ("Pantry", "include_week_start"), ("HouseholdExport", "planning_preferences"), ("HouseholdExport", "accepted_suggestions")]:
    candidates = [schemas[n] for n in (name, name+"-Input", name+"-Output") if n in schemas]
    assert candidates, name
    for candidate in candidates:
        assert field in candidate["properties"]
        assert field not in candidate.get("required", []), (name, field)
assert "recognized_text" in schemas["RecipeImportStatus"]["properties"]

assert "source_photo" in schemas["RecipeImportStatus"]["properties"]
assert "source_photo" not in schemas["RecipeImportStatus"].get("required", [])

# Food onboarding is an additive PWA resource; native entity sync remains unchanged.
food = schema["paths"]["/api/v1/household/food-profile"]
assert {"get", "put"}.issubset(food)
assert set(schemas["FoodProfile"]["properties"]) == {"likes", "dislikes", "pantry_setup_done", "taste_setup_done"}
assert "preferences" not in schemas["IdeaRequest"].get("required", [])
assert "food_profile" not in schemas["HouseholdExport"]["required"]
assert schemas["HouseholdExport"]["properties"]["version"]["default"] == 4
