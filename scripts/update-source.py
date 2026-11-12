#!/usr/bin/env python3
"""Generate an AltStore/FlareStore feed from the actual built IPAs, never guessed versions/sizes."""
import argparse
import datetime
import json
import plistlib
import re
import zipfile
from pathlib import Path

REPO = '9pbpsvr6f9-alt/aiostreams-ios'
APPS = [('AIOStreams.ipa', 'io.github.aiostreams-ios.app', 'AIOStreams for iPhone and iPad'),
        ('AIOStreams-tvOS.ipa', 'io.github.aiostreams-ios.tv', 'AIOStreams for Apple TV')]

def metadata(ipa, expected):
    with zipfile.ZipFile(ipa) as archive:
        names = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if len(names) != 1:
            raise ValueError('Expected exactly one application Info.plist')
        info = plistlib.loads(archive.read(names[0]))
    if info['CFBundleIdentifier'] != expected:
        raise ValueError('Unexpected bundle identifier')
    return info

def generate(tag, folder, previous=None):
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Expected a vMAJOR.MINOR.PATCH release tag')
    incoming = tuple(map(int, tag[1:].split('.')))
    for app in (previous or {}).get('apps', []):
        if app.get('versions'):
            current = tuple(map(int, app['versions'][0]['version'].split('.')))
            if incoming < current:
                raise ValueError('Refusing to publish an older source version')
    source = {'name': 'AIOStreams — 9pbpsvr6f9-alt',
              'identifier': 'io.github.9pbpsvr6f9-alt.aiostreams',
              'subtitle': 'Unofficial iOS and tvOS builds',
              'description': 'Unsigned AIOStreams builds. Your sideloading tool signs each app at installation.',
              'website': f'https://github.com/{REPO}',
              'iconURL': f'https://github.com/{REPO}/releases/latest/download/icon.png',
              'tintColor': '#1C1C1E', 'apps': [], 'news': []}
    for filename, bundle, name in APPS:
        ipa = folder / filename
        info = metadata(ipa, bundle)
        if info['CFBundleShortVersionString'] != tag[1:]:
            raise ValueError('Release tag and IPA marketing version differ')
        old = next((a for a in (previous or {}).get('apps', []) if a['bundleIdentifier'] == bundle), {})
        entry = {'version': info['CFBundleShortVersionString'], 'buildVersion': str(info['CFBundleVersion']),
                 'date': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                 'localizedDescription': f'Release notes: https://github.com/{REPO}/releases/tag/{tag}',
                 'downloadURL': f'https://github.com/{REPO}/releases/download/{tag}/{filename}',
                 'size': ipa.stat().st_size, 'minOSVersion': info.get('MinimumOSVersion', '18.0')}
        versions = [entry] + [v for v in old.get('versions', []) if v['version'] != entry['version']]
        privacy = {k: v for k, v in info.items() if k.startswith('NS') and k.endswith('UsageDescription')}
        source['apps'].append({'name': name, 'bundleIdentifier': bundle, 'developerName': '9pbpsvr6f9-alt',
                               'localizedDescription': 'Unofficial AIOStreams with AetherEngine. Sign with your sideloading tool.',
                               'iconURL': source['iconURL'], 'category': 'entertainment',
                               'versions': versions[:30],
                               'appPermissions': {'entitlements': [], 'privacy': privacy}})
    return source

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--folder', type=Path, default=Path('build'))
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--output', type=Path, default=Path('altstore/source.json'))
    args = parser.parse_args()
    previous = json.loads(args.previous.read_text()) if args.previous else None
    source = generate(args.tag, args.folder, previous)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(source, indent=2) + '\n')
    print('Generated release source for both verified IPA bundles.')

if __name__ == '__main__':
    main()
