#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-target.sh
source Scripts/swift-sources.sh
python3 - <<'PY'
import json, pathlib, re, subprocess
root = pathlib.Path('.')
def strings(language):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', f'Resources/{language}.lproj/Localizable.strings']))
zh, en = strings('zh-Hans'), strings('en')
keys = {json.loads('"'+s+'"') for p in (root/'Sources').rglob('*.swift')
        for s in re.findall(r'\bL\("((?:\\.|[^"\\])*)"', p.read_text())}
assert keys <= zh.keys() == en.keys(), f'Missing localization: {keys - zh.keys()} / {keys - en.keys()} / diff: {zh.keys() ^ en.keys()}'
for key in keys:
    assert zh[key] == key
    assert key.count('%@') == en[key].count('%@'), f'Format mismatch: {key}'
    assert not re.search(r'[\u3400-\u9fff]', en[key]), f'Untranslated English value: {key}'
manifest = (root/'Scripts/swift-sources.sh').read_text()
referenced = set(re.findall(r'Sources/[A-Za-z0-9_/.-]+\.(?:swift|h)', manifest))
for path in referenced:
    assert (root/path).is_file(), f'Missing file referenced in swift-sources.sh: {path}'
actual_swift = {p.as_posix() for p in (root/'Sources').rglob('*.swift')}
referenced_swift = {p for p in referenced if p.endswith('.swift')}
assert actual_swift == referenced_swift, f'Source manifest drift: {actual_swift ^ referenced_swift}'
print(f'PASS: {len(keys)} UI/status localization keys, format arguments and {len(actual_swift)} manifest Swift sources.')
PY
mkdir -p build/tests
xcrun swiftc "${remote_vibe_swift_flags[@]}" \
  "${rv_app_support_sources[@]}" Tests/app_support_test.swift \
  -o build/tests/app-support
build/tests/app-support
