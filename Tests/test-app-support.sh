#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
python3 - <<'PY'
import json, pathlib, re, subprocess
root = pathlib.Path('.')
def strings(language):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', f'Resources/{language}.lproj/Localizable.strings']))
zh, en = strings('zh-Hans'), strings('en')
keys = {json.loads('"'+s+'"') for p in (root/'Sources').rglob('*.swift')
        for s in re.findall(r'L\("((?:\\.|[^"\\])*)"', p.read_text())}
assert keys <= zh.keys() == en.keys(), f'Missing localization: {keys - zh.keys()} / {keys - en.keys()}'
for key in keys:
    assert zh[key] == key
    assert key.count('%@') == en[key].count('%@'), f'Format mismatch: {key}'
    assert not re.search(r'[\u3400-\u9fff]', en[key]), f'Untranslated English value: {key}'
print(f'PASS: {len(keys)} UI/status localization keys and format arguments.')
PY
mkdir -p build/tests
xcrun swiftc -swift-version 5 -parse-as-library -target "$remote_vibe_swift_target" \
  Sources/App/Localization.swift Sources/App/ReleaseUpdate.swift Tests/app_support_test.swift \
  -o build/tests/app-support
build/tests/app-support
