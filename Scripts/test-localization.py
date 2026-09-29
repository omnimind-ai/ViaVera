#!/usr/bin/env python3
"""Validate catalogs and built language selection without launching the app.

Usage: python3 Scripts/test-localization.py --app '/path/to/Via Vera.app'
Pass --stringsdata /path/to/Objects-normal/arm64 to check compiler-extracted keys.
"""
import argparse
import collections
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FORMAT = re.compile(r'%%|%(?:\d+\$)?(?:lld|llu|ld|lu|zd|zu|d|u|@|lf|f|g)')


def placeholders(value):
    return collections.Counter(m[0] for m in FORMAT.finditer(value) if m[0] != '%%')


def validate_catalogs():
    catalogs = {}
    for name in ('Localizable', 'InfoPlist'):
        catalog = json.loads((ROOT / 'OmniBot/Resources' / f'{name}.xcstrings').read_text())
        assert catalog['sourceLanguage'] == 'en'
        for key, entry in catalog['strings'].items():
            assert set(entry['localizations']) == {'en', 'zh-Hans'}, key
            for language, localization in entry['localizations'].items():
                unit = localization['stringUnit']
                assert unit['state'] == 'translated', (key, language)
                assert unit['value'] or not key, (key, language)
                if name == 'Localizable':
                    assert placeholders(key) == placeholders(unit['value']), (key, language)
                if language == 'en':
                    assert not re.search(r'[\u4e00-\u9fff]', unit['value']), key
        catalogs[name] = catalog
        print(f'PASS: {name}, {len(catalog["strings"])} bilingual entries')
    info = plistlib.loads((ROOT / 'OmniBot/Info.plist').read_bytes())
    privacy_keys = {key for key in info if key.endswith('UsageDescription')}
    assert privacy_keys <= set(catalogs['InfoPlist']['strings'])
    for key in privacy_keys:
        assert info[key] == catalogs['InfoPlist']['strings'][key]['localizations']['en']['stringUnit']['value']
    return catalogs


def validate_extraction(directory, catalogs):
    count = 0
    files = list(directory.glob('*.stringsdata'))
    assert files, f'No compiler extraction files in {directory}'
    for path in files:
        extracted = json.loads(path.read_text())
        for table, entries in extracted.get('tables', {}).items():
            for entry in entries:
                key = entry['key']
                if re.search(r'[\u4e00-\u9fff]', key):
                    assert key in catalogs[table]['strings'], (path.name, key)
                    count += 1
    print(f'PASS: {count} extracted localized call sites covered in {directory}')


def validate_app(app, catalogs):
    # On macOS, secondary bundles follow the main bundle's language. Package only
    # this headless probe and the built language resources to exercise that rule.
    resources = app / 'Contents/Resources' if (app / 'Contents').is_dir() else app
    info_path = app / 'Contents/Info.plist' if (app / 'Contents').is_dir() else app / 'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    assert info['CFBundleDevelopmentRegion'] == 'en'
    for language in ('en', 'zh-Hans'):
        for table, catalog in catalogs.items():
            compiled = json.loads(subprocess.check_output([
                'plutil', '-convert', 'json', '-o', '-',
                str(resources / f'{language}.lproj' / f'{table}.strings'),
            ]))
            for key, entry in catalog['strings'].items():
                assert compiled[key] == entry['localizations'][language]['stringUnit']['value'], (language, key)
    with tempfile.TemporaryDirectory(prefix='omnibot-language-test-') as temporary:
        contents = Path(temporary) / 'LocalizationProbe.app/Contents'
        executable = contents / 'MacOS/LocalizationProbe'
        executable.parent.mkdir(parents=True)
        (contents / 'Resources').mkdir()
        for directory in resources.glob('*.lproj'):
            shutil.copytree(directory, contents / 'Resources' / directory.name)
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': 'LocalizationProbe',
            'CFBundleIdentifier': 'test.omnibot.localization-probe',
            'CFBundleDevelopmentRegion': info['CFBundleDevelopmentRegion'],
            'CFBundlePackageType': 'APPL',
        }))
        main_source = Path(temporary) / 'main.swift'
        shutil.copyfile(ROOT / 'Scripts/Localization/LocalizationProbe.swift', main_source)
        model_sources = [
            'OmniBot/Features/Settings/Shell/SettingsCardDestination.swift',
            'OmniBot/App/Settings/Permissions/IOSPermissionKind.swift',
            'OmniBot/App/Settings/Usage/ModelUsageRange.swift',
            'OmniBot/Features/Sidebar/SidebarConversationGroup.swift',
            'OmniBot/Features/Chat/ToolActivity/ToolCallStatus.swift',
        ]
        subprocess.run(['xcrun', 'swiftc', str(main_source),
                        *[str(ROOT / path) for path in model_sources],
                        '-o', str(executable)], check=True)
        cases = [
            ('(en)', 'zh_CN', 'en'),
            ('(en-GB)', 'en_GB', 'en'),
            ('(zh-Hans)', 'en_US', 'zh-Hans'),
            ('(zh-Hans-CN)', 'zh_CN', 'zh-Hans'),
            ('(fr)', 'fr_FR', 'en'),
            ('(de,zh-Hans,en)', 'de_DE', 'zh-Hans'),
            ('(en,zh-Hans)', 'zh_CN', 'en'),
        ]
        for languages, region, expected in cases:
            subprocess.run([str(executable), str(app), expected, '-AppleLanguages', languages,
                            '-AppleLocale', region], check=True)
    print(f'PASS: compiled resources and seven language/region cases for {app.name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--stringsdata', type=Path, action='append', default=[])
    args = parser.parse_args()
    catalogs = validate_catalogs()
    for directory in args.stringsdata:
        validate_extraction(directory, catalogs)
    if args.app:
        validate_app(args.app.resolve(), catalogs)


if __name__ == '__main__':
    main()
