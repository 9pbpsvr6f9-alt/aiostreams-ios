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
RAW = f'https://raw.githubusercontent.com/{REPO}/main'
# The address to add, served without a redirect: FlareStore keeps the address a redirect ends on,
# and the release asset's address ends on that one release, which never changes again.
SOURCE_URL = f'{RAW}/altstore/source.json'
TINT = '#6152DF'
# Older versions stay installable from the source for this many releases.
HISTORY = 50
NEWS = 10

APPS = [('AIOStreams.ipa', 'io.github.aiostreams-ios.app', 'AIOStreams'),
        ('AIOStreams-tvOS.ipa', 'io.github.aiostreams-ios.tv', 'AIOStreams for Apple TV')]

DETAILS = {
    'io.github.aiostreams-ios.app': {
        'subtitle': 'AIOStreams and Jellyfin, played properly',
        'description': (
            'A native iPhone and iPad app for your AIOStreams and Jellyfin library. It plays through '
            'AetherEngine, so Dolby Vision, HDR10, HDR10+, Atmos and image subtitles work where '
            'Safari and AVPlayer give up.\n\n'
            '• Smart downloads keep the next episodes of a show on your device and remove them once watched\n'
            '• Downloads carry on in the background, play offline and sync what you watched later\n'
            '• A skip intro countdown, Picture in Picture that hands off to the mini player, and trailers\n'
            '• Subtitles in your own style, spoiler blur, brightness and volume swipes, light haptics\n'
            '• Optional anime upscaling on iOS 26\n\n'
            'Unofficial and unsigned: your sideloading tool signs it when you install.'),
        'screenshots': ['iphone-home', 'iphone-show', 'iphone-movie', 'iphone-versions'],
        'ipad': ['ipad-home', 'ipad-show'],
    },
    'io.github.aiostreams-ios.tv': {
        'subtitle': 'Your Jellyfin library on the big screen',
        'description': (
            'A native Apple TV app over your server, playing through AetherEngine with HDR10, '
            'Dolby Vision and Atmos.\n\n'
            '• Home with a rotating hero and Continue watching\n'
            '• Show and movie pages, a version picker and synced settings\n\n'
            'Unofficial and unsigned: your sideloading tool signs it when you install.'),
        'screenshots': ['tv-home', 'tv-show', 'tv-movie', 'tv-versions', 'tv-player'],
        'ipad': [],
    },
}


def shot(name):
    return f'{RAW}/docs/screenshots/{name}.jpg'


def metadata(ipa, expected):
    with zipfile.ZipFile(ipa) as archive:
        names = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if len(names) != 1:
            raise ValueError('Expected exactly one application Info.plist')
        info = plistlib.loads(archive.read(names[0]))
    if info['CFBundleIdentifier'] != expected:
        raise ValueError('Unexpected bundle identifier')
    return info


def clean_notes(notes):
    """Release notes as short bullet lines: no blanks, no addresses, at most 12."""
    lines = []
    for line in (notes or '').splitlines():
        line = line.strip().lstrip('-•* ').strip()
        # The release job's own commit of the source to main is bookkeeping, not a change.
        if line.startswith('FlareStore source: '):
            continue
        if line and '@' not in line and line not in lines:
            lines.append(line)
    return lines[:12]


def generate(tag, folder, previous=None, notes=None):
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Expected a vMAJOR.MINOR.PATCH release tag')
    incoming = tuple(map(int, tag[1:].split('.')))
    for app in (previous or {}).get('apps', []):
        if app.get('versions'):
            current = tuple(map(int, app['versions'][0]['version'].split('.')))
            if incoming < current:
                raise ValueError('Refusing to publish an older source version')
    changes = clean_notes(notes)
    released = datetime.datetime.now(datetime.timezone.utc).isoformat()
    release_page = f'https://github.com/{REPO}/releases/tag/{tag}'
    what = '\n'.join(f'• {line}' for line in changes) if changes else 'Fixes and improvements.'
    source = {'name': 'AIOStreams',
              'identifier': 'io.github.9pbpsvr6f9-alt.aiostreams',
              'subtitle': 'Jellyfin on iPhone, iPad and Apple TV',
              'description': ('Native AIOStreams apps for iPhone, iPad and Apple TV, made for watching and '
                              'playing through AetherEngine. Every update says what changed, and earlier '
                              'versions stay installable from the version history. Your sideloading tool '
                              'signs each app when you install it.'),
              'website': f'https://github.com/{REPO}',
              'sourceURL': SOURCE_URL,
              'iconURL': f'{RAW}/altstore/icon.png',
              'headerURL': shot('tv-home'),
              'tintColor': TINT, 'featuredApps': [b for _, b, _ in APPS], 'apps': [], 'news': []}
    for filename, bundle, name in APPS:
        ipa = folder / filename
        info = metadata(ipa, bundle)
        if info['CFBundleShortVersionString'] != tag[1:]:
            raise ValueError('Release tag and IPA marketing version differ')
        old = next((a for a in (previous or {}).get('apps', []) if a['bundleIdentifier'] == bundle), {})
        entry = {'version': info['CFBundleShortVersionString'], 'buildVersion': str(info['CFBundleVersion']),
                 'date': released,
                 'localizedDescription': f"What's new\n{what}\n\nFull notes: {release_page}",
                 'downloadURL': f'https://github.com/{REPO}/releases/download/{tag}/{filename}',
                 'size': ipa.stat().st_size, 'minOSVersion': info.get('MinimumOSVersion', '18.0')}
        versions = [entry] + [v for v in old.get('versions', []) if v['version'] != entry['version']]
        privacy = {k: v for k, v in info.items() if k.startswith('NS') and k.endswith('UsageDescription')}
        details = DETAILS[bundle]
        screenshots = [shot(s) for s in details['screenshots']]
        app = {'name': name, 'bundleIdentifier': bundle, 'developerName': '9pbpsvr6f9-alt',
               'subtitle': details['subtitle'],
               'localizedDescription': details['description'],
               'iconURL': source['iconURL'], 'tintColor': TINT, 'category': 'entertainment',
               'screenshotURLs': screenshots,
               'versions': versions[:HISTORY],
               'appPermissions': {'entitlements': [], 'privacy': privacy}}
        if details['ipad']:
            app['screenshots'] = {'iphone': screenshots, 'ipad': [shot(s) for s in details['ipad']]}
        source['apps'].append(app)
    # One news item per release, newest first, linking to the iPhone app.
    news = {'identifier': f'release-{tag}', 'title': f'AIOStreams {tag[1:]}',
            'caption': changes[0] if changes else 'A new version is ready to install.',
            'date': released, 'tintColor': TINT, 'appID': APPS[0][1], 'url': release_page,
            'notify': False}
    earlier = [n for n in (previous or {}).get('news', []) if n.get('identifier') != news['identifier']]
    source['news'] = [news] + earlier[:NEWS - 1]
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--folder', type=Path, default=Path('build'))
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--notes', type=Path, help='What changed, one line each (commit titles)')
    parser.add_argument('--output', type=Path, default=Path('altstore/source.json'))
    args = parser.parse_args()
    previous = json.loads(args.previous.read_text()) if args.previous else None
    notes = args.notes.read_text() if args.notes and args.notes.exists() else None
    source = generate(args.tag, args.folder, previous, notes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(source, indent=2) + '\n')
    print('Generated release source for both verified IPA bundles.')


if __name__ == '__main__':
    main()
