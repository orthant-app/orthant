#!/usr/bin/env python3
"""Writes the winget manifest for one stable Windows release: the three files
the community repository takes (version, installer, defaultLocale), schema
1.12.0, the one its pull request template asks for.

  winget_manifest.py --version 1.1.0 --sha256 <installer's SHA-256>
      --date 2026-10-20 --out build/winget

Writes <out>/Orthant.Orthant.yaml, Orthant.Orthant.installer.yaml and
Orthant.Orthant.locale.en-US.yaml, and prints the folder. The installer's URL
is the release's own asset, named from the version, as windows-feed names it.
Every field is written each time (nothing is inherited from an earlier
version's manifest), so what a release submits is what this script and its
test say.

Refuses, writing nothing: a version that is not three integers (winget
carries stable releases only), a SHA-256 that is not 64 hex digits, a date
that is not YYYY-MM-DD.
"""
import argparse
import os
import re
import sys

IDENTIFIER = 'Orthant.Orthant'
SCHEMA = '1.12.0'
# The installer's AppId with Inno's suffix: the key Windows lists an
# installed copy under, which winget matches to this package.
PRODUCT_CODE = '{2CB97B64-A74B-4CDD-8EB5-5C67F7689DDD}_is1'
# The installer's own MinVersion (Windows 10 1809).
MINIMUM_OS = '10.0.17763.0'
RELEASES = 'https://github.com/orthant-app/orthant/releases/download'


def fail(why):
    print(f'winget_manifest: {why}', file=sys.stderr)
    sys.exit(1)


def header(kind):
    return f'# yaml-language-server: $schema=https://aka.ms/winget-manifest.{kind}.{SCHEMA}.schema.json'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--version', required=True)
    p.add_argument('--sha256', required=True)
    p.add_argument('--date', required=True)
    p.add_argument('--out', required=True)
    a = p.parse_args()

    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', a.version):
        fail(f'{a.version!r} is not a stable version (three integers)')
    if not re.fullmatch(r'[0-9A-Fa-f]{64}', a.sha256):
        fail(f'{a.sha256!r} is not a SHA-256')
    if not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', a.date):
        fail(f'{a.date!r} is not YYYY-MM-DD')

    url = f'{RELEASES}/v{a.version}/Orthant-{a.version}-setup.exe'
    files = {
        f'{IDENTIFIER}.yaml': [
            header('version'),
            f'PackageIdentifier: {IDENTIFIER}',
            f'PackageVersion: {a.version}',
            'DefaultLocale: en-US',
            'ManifestType: version',
            f'ManifestVersion: {SCHEMA}',
        ],
        f'{IDENTIFIER}.installer.yaml': [
            header('installer'),
            f'PackageIdentifier: {IDENTIFIER}',
            f'PackageVersion: {a.version}',
            'InstallerType: inno',
            'Scope: user',
            'InstallModes:',
            '- interactive',
            '- silent',
            '- silentWithProgress',
            'UpgradeBehavior: install',
            f"ProductCode: '{PRODUCT_CODE}'",
            f'ReleaseDate: {a.date}',
            f'MinimumOSVersion: {MINIMUM_OS}',
            'Installers:',
            '- Architecture: x64',
            f'  InstallerUrl: {url}',
            f'  InstallerSha256: {a.sha256.upper()}',
            'ManifestType: installer',
            f'ManifestVersion: {SCHEMA}',
        ],
        f'{IDENTIFIER}.locale.en-US.yaml': [
            header('defaultLocale'),
            f'PackageIdentifier: {IDENTIFIER}',
            f'PackageVersion: {a.version}',
            'PackageLocale: en-US',
            'Publisher: Orthant',
            'PublisherUrl: https://orthant.app',
            'PublisherSupportUrl: https://github.com/orthant-app/orthant/issues',
            'PackageName: Orthant',
            'PackageUrl: https://orthant.app',
            'License: MIT',
            'LicenseUrl: https://github.com/orthant-app/orthant/blob/main/LICENSE',
            'ShortDescription: Grid-based window manager. Snap the frontmost window with keyboard shortcuts, or draw where it goes on a grid.',
            'Moniker: orthant',
            'Tags:',
            '- window-manager',
            '- tiling',
            '- keyboard-shortcuts',
            '- productivity',
            'ReleaseNotesUrl: https://orthant.app/changelog/',
            'ManifestType: defaultLocale',
            f'ManifestVersion: {SCHEMA}',
        ],
    }
    os.makedirs(a.out, exist_ok=True)
    for name, lines in files.items():
        with open(os.path.join(a.out, name), 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(lines) + '\n')
    print(a.out)


if __name__ == '__main__':
    main()
