import json
import re

with open(r'C:\Users\ASUS\.gemini\antigravity\brain\b945560e-cfbd-43ac-8e74-340901d3513d\.system_generated\steps\504\output.txt', 'r', encoding='utf-8') as f:
    text = f.read()

match = re.search(r'\[\s*\{.*\}\s*\]', text, re.DOTALL)
if match:
    raw_str = match.group(0).strip().replace('\\"', '"')
    # sometimes there are nested escapes, remove escaping correctly
    raw_str = raw_str.encode('utf-8').decode('unicode_escape') if '\\' in raw_str else raw_str
    try:
        rows = json.loads(raw_str)
    except:
        # direct json string parse fallback
        import ast
        rows = ast.literal_eval(match.group(0).strip())
    db_rockets = rows[0].get('rocket_custom_definitions', [])
else:
    db_rockets = []

with open(r'C:\Users\ASUS\Desktop\hatStar\rocket_tiers.json', 'r', encoding='utf-8') as f:
    new_rockets = json.loads(f.read())

result = []
for i, r in enumerate(new_rockets):
    r_id = 2000000000000 + i # Default ID
    if i < len(db_rockets):
        r_db = db_rockets[i]
        r_id = r_db.get('id', r_id)
        # Preserve specific keys
        r['name'] = r_db.get('name', r['name'])
        
        # keep images
        r['full'] = r_db.get('full', {'shape': 'rocket', 'color': '0xFFE53935', 'image_url': ''})
        r['booster'] = r_db.get('booster', {'shape': 'square', 'color': '0xFFE53935', 'image_url': ''})
        
        db_capsule = r_db.get('capsule', {})
        new_capsule = {'shape': 'circle', 'color': '0xFF607D8B', 'image_url': db_capsule.get('image_url', ''), 'thrust_multiplier': db_capsule.get('thrust_multiplier', 1.2)}
        r['capsule'] = new_capsule
    else:
        # Default images for 5-10
        r['full'] = {'shape': 'rocket', 'color': '0xFFE53935', 'image_url': ''}
        r['booster'] = {'shape': 'square', 'color': '0xFFE53935', 'image_url': ''}
        r['capsule'] = {'shape': 'circle', 'color': '0xFF607D8B', 'image_url': '', 'thrust_multiplier': 1.2 + (i*0.2)}

    r['id'] = r_id
    result.append(r)

with open(r'C:\Users\ASUS\Desktop\hatStar\merged_rockets.sql', 'w', encoding='utf-8') as f:
    json_str = json.dumps(result, ensure_ascii=False)
    json_str = json_str.replace("'", "''")
    sql = f"UPDATE space_game_settings SET rocket_custom_definitions = '{json_str}'::jsonb WHERE id = 1;"
    f.write(sql)

print('SQL saved to merged_rockets.sql')
