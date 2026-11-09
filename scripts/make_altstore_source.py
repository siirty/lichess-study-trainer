#!/usr/bin/env python3
"""Generate accurate AltStore metadata from the built device IPA, not a simulator."""
import argparse
import datetime
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('ipa', type=Path)
parser.add_argument('--download-url', required=True)
parser.add_argument('--output', type=Path, default=Path('altstore-source.json'))
args = parser.parse_args()
if not args.download_url.startswith('https://github.com/siirty/lichess-study-trainer/releases/download/'):
    raise SystemExit('Use the public repository release asset URL')
with zipfile.ZipFile(args.ipa) as archive:
    info = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
    binary = archive.read('Payload/Runner.app/' + info['CFBundleExecutable'])
    magic, cpu = struct.unpack_from('<II', binary)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise SystemExit('An arm64 iPhone device app is required')
    if info['CFBundleIdentifier'] != 'org.studytrainer.standalone':
        raise SystemExit('Unexpected app identity')
    if any('.appex/' in name for name in archive.namelist()):
        raise SystemExit('Review source permissions before distributing app extensions')
    privacy = {key: value for key, value in info.items() if key.endswith('UsageDescription')}
icon = 'https://raw.githubusercontent.com/siirty/lichess-study-trainer/main/apps/standalone/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png'
source = {
    'name': 'Study Trainer',
    'subtitle': 'Offline Lichess study practice',
    'description': 'Independent GPL study trainer. Free personal signing through AltStore Classic; refresh every seven days. Not affiliated with Lichess.',
    'iconURL': icon,
    'website': 'https://github.com/siirty/lichess-study-trainer',
    'tintColor': '#629924',
    'apps': [{
        'name': 'Study Trainer',
        'bundleIdentifier': info['CFBundleIdentifier'],
        'developerName': 'Study Trainer contributors',
        'localizedDescription': 'Import Lichess studies or PGN, train either side, and keep spaced-repetition progress offline. Includes hints, review history and backups. Independent engineering preview; no account required for local PGN.',
        'iconURL': icon,
        'versions': [{
            'version': info['CFBundleShortVersionString'],
            'buildVersion': info['CFBundleVersion'],
            'marketingVersion': 'iOS preview ' + info['CFBundleShortVersionString'],
            'date': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'downloadURL': args.download_url,
            'size': args.ipa.stat().st_size,
            'minOSVersion': info['MinimumOSVersion'],
            'localizedDescription': 'Native iPhone build. Sign locally with AltStore Classic. Free-account installations require seven-day renewal.',
        }],
        'appPermissions': {'entitlements': ['keychain-access-groups'], 'privacy': privacy},
    }],
    'news': [],
}
args.output.write_text(json.dumps(source, indent=2) + '\n')
with args.ipa.open('rb') as stream:
    print('IPA SHA-256:', hashlib.file_digest(stream, 'sha256').hexdigest())
print('Generated', args.output, 'from iPhoneOS app', info['CFBundleShortVersionString'], info['CFBundleVersion'])
