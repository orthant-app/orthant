#!/usr/bin/env python3
"""Writes a Windows appcast: the new installer's item first, then every item
of the feed it replaces.

  windows_appcast.py --out appcast-win.xml [--history appcast-win.xml]
      --installer build/dist/Orthant-1.1.0-setup.exe --release-name 1.1.0
      --build 8 --url https://github.com/orthant-app/orthant/releases/download/v1.1.0/Orthant-1.1.0-setup.exe
      --sign-line 'sparkle:edSignature="..." length="..."'

--sign-line is what Sparkle's sign_update prints for the installer: its
Ed25519 signature, which WinSparkle verifies against the key compiled into
the app, and the length it signed, which must be the installer's. The
format is macOS's feed's (one <item> per release, newest first), plus what
WinSparkle reads that Sparkle does not: sparkle:os, so a future build for
another architecture can share the feed, and sparkle:installerArguments, so
an update runs the installer without its wizard and the app comes back.

Refuses, writing nothing: a build number not above every earlier item's (the
counter is shared with macOS and only ever grows; an update is offered only
for a higher one); a --history that names no file (a first release passes
none, so a feed that failed to arrive cannot pass for one); a URL that does
not end in the installer's file name; a signature that is not 64 bytes of
base64; a length that is not the file's; an earlier item holding anything
this script does not write, which it would otherwise drop. Whether the
signature is this installer's is not checked here: WinSparkle checks it on
every client before it runs anything.
"""
import argparse
import base64
import email.utils
import os
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
MIN_WINDOWS = '10.0.17763'
OS_MARKER = 'windows-x64'
INSTALLER_ARGUMENTS = '/SILENT /SP- /NOCANCEL /SUPPRESSMSGBOXES /RELAUNCH=1'
ITEM_CHILDREN = {'title', 'pubDate', '{%s}version' % SPARKLE,
                 '{%s}shortVersionString' % SPARKLE,
                 '{%s}minimumSystemVersion' % SPARKLE, 'enclosure'}
REQUIRED_CHILDREN = ITEM_CHILDREN - {'{%s}minimumSystemVersion' % SPARKLE}
ENCLOSURE_ATTRS = {'url', 'length', 'type', '{%s}edSignature' % SPARKLE,
                   '{%s}os' % SPARKLE, '{%s}installerArguments' % SPARKLE}


def fail(why):
    print(f'windows_appcast: {why}', file=sys.stderr)
    sys.exit(1)


def read_history(path):
    """Every item of an earlier feed, as the fields this script writes."""
    if path is None:
        return []
    if not os.path.exists(path):
        fail(f'no history at {path}: a first release passes no --history')
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        fail(f'{path} is not XML: {e}')
    channel = root.find('channel')
    if root.tag != 'rss' or channel is None:
        fail(f'{path} is not an RSS feed')
    items = []
    for item in channel.findall('item'):
        unknown = {c.tag for c in item} - ITEM_CHILDREN
        if unknown:
            fail(f'{path} has an item with {sorted(unknown)}, which this script would drop')
        # Rewritten from these fields alone, so anything else they could hold
        # (a second enclosure, an attribute, something nested) would be lost.
        if item.attrib:
            fail(f'{path} has an item with attributes {sorted(item.attrib)}, which this script would drop')
        for tag in ITEM_CHILDREN:
            found = item.findall(tag)
            if len(found) > 1 or (not found and tag in REQUIRED_CHILDREN):
                fail(f'{path} has an item with {len(found)} {tag}, where this script writes one')
        for child in item:
            if len(child) or (child.tag != 'enclosure' and child.attrib):
                fail(f'{path} has an item whose {child.tag} holds more than text, which this script would drop')
        enclosure = item.find('enclosure')
        extra = set(enclosure.attrib) - ENCLOSURE_ATTRS
        if extra:
            fail(f'{path} has an enclosure with {sorted(extra)}, which this script would drop')

        def text(tag):
            node = item.find(tag)
            return (node.text or '').strip() if node is not None else ''
        version = text('{%s}version' % SPARKLE)
        if not version.isdigit():
            fail(f'{path} has an item whose sparkle:version is {version!r}')
        items.append({
            'title': text('title'),
            'pubDate': text('pubDate'),
            'version': version,
            'short': text('{%s}shortVersionString' % SPARKLE),
            'minimum': text('{%s}minimumSystemVersion' % SPARKLE),
            'enclosure': dict(enclosure.attrib),
        })
    return items


def write_item(out, item):
    e = item['enclosure']
    out.append('        <item>')
    out.append(f'            <title>{escape(item["title"])}</title>')
    out.append(f'            <pubDate>{escape(item["pubDate"])}</pubDate>')
    out.append(f'            <sparkle:version>{escape(item["version"])}</sparkle:version>')
    out.append(f'            <sparkle:shortVersionString>{escape(item["short"])}</sparkle:shortVersionString>')
    if item['minimum']:
        out.append(f'            <sparkle:minimumSystemVersion>{escape(item["minimum"])}</sparkle:minimumSystemVersion>')
    attrs = [('url', e['url']), ('length', e['length']), ('type', e['type']),
             ('sparkle:os', e.get('{%s}os' % SPARKLE, '')),
             ('sparkle:installerArguments', e.get('{%s}installerArguments' % SPARKLE, '')),
             ('sparkle:edSignature', e['{%s}edSignature' % SPARKLE])]
    rendered = ' '.join(f'{k}={quoteattr(v)}' for k, v in attrs if v != '')
    out.append(f'            <enclosure {rendered}/>')
    out.append('        </item>')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', required=True)
    p.add_argument('--history')
    p.add_argument('--installer', required=True)
    p.add_argument('--release-name', required=True)
    p.add_argument('--build', required=True)
    p.add_argument('--url', required=True)
    p.add_argument('--sign-line', required=True)
    p.add_argument('--date', help='RFC 2822; now when absent')
    a = p.parse_args()

    if not re.fullmatch(r'[1-9][0-9]*', a.build):
        fail(f'build {a.build!r} is not a positive integer')
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?', a.release_name):
        fail(f'release name {a.release_name!r} is not a version')
    if not os.path.isfile(a.installer):
        fail(f'no installer at {a.installer}')
    name = os.path.basename(a.installer)
    if not a.url.endswith('/' + name):
        fail(f'the URL {a.url} does not end in the installer\'s name, {name}')
    m = re.fullmatch(r'\s*sparkle:edSignature="([A-Za-z0-9+/]+={0,2})"\s+length="([0-9]+)"\s*', a.sign_line)
    if not m:
        fail(f'not a sign_update line: {a.sign_line!r}')
    signature, length = m.group(1), m.group(2)
    try:
        raw = base64.b64decode(signature, validate=True)
    except ValueError:
        fail('the signature is not base64')
    if len(raw) != 64:
        fail('the signature is not 64 bytes, as an Ed25519 signature is')
    size = os.path.getsize(a.installer)
    if int(length) != size:
        fail(f'sign_update signed {length} bytes; the installer is {size}')

    history = read_history(a.history)
    newer = [h for h in history if int(h['version']) >= int(a.build)]
    if newer:
        fail(f'build {a.build} is not above every earlier item: '
             + ', '.join(f'{h["short"]} ({h["version"]})' for h in newer))

    item = {
        'title': a.release_name,
        'pubDate': a.date or email.utils.formatdate(usegmt=True),
        'version': a.build,
        'short': a.release_name,
        'minimum': MIN_WINDOWS,
        'enclosure': {
            'url': a.url, 'length': str(size), 'type': 'application/octet-stream',
            '{%s}os' % SPARKLE: OS_MARKER,
            '{%s}installerArguments' % SPARKLE: INSTALLER_ARGUMENTS,
            '{%s}edSignature' % SPARKLE: signature,
        },
    }
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           f'<rss xmlns:sparkle="{SPARKLE}" version="2.0">',
           '    <channel>',
           '        <title>Orthant</title>']
    for i in [item] + sorted(history, key=lambda h: int(h['version']), reverse=True):
        write_item(out, i)
    out += ['    </channel>', '</rss>', '']
    text = '\n'.join(out)
    ET.fromstring(text.encode('utf-8'))  # what it wrote parses
    tmp = a.out + '.partial'
    with open(tmp, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    os.replace(tmp, a.out)
    print(f'{a.out}: {a.release_name} ({a.build}) and {len(history)} earlier item(s)')


if __name__ == '__main__':
    main()
