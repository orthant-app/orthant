#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/windows_appcast.py"
TMP_DIR="$(mktemp -d)"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s\n' "$1" >&2
}

assert_ok() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

assert_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then fail "$label (unexpected success)"; else pass "$label"; fi
}

# A stand-in installer of a known size, and a signature line for it in
# sign_update's form (64 bytes of zeros, base64, is the right shape).
SIG="$(printf '%064d' 0 | head -c 64 | base64 | tr -d '\n')"
installer() { # name size
  head -c "$2" /dev/zero >"$TMP_DIR/$1"
  printf 'sparkle:edSignature="%s" length="%s"' "$SIG" "$2"
}
URL1='https://github.com/orthant-app/orthant/releases/download/v1.1.0/Orthant-1.1.0-setup.exe'
URL2='https://github.com/orthant-app/orthant/releases/download/v1.2.0-beta.1/Orthant-1.2.0-beta.1-setup.exe'
LINE1="$(installer Orthant-1.1.0-setup.exe 1000)"
LINE2="$(installer Orthant-1.2.0-beta.1-setup.exe 2000)"

gen() { # out history installer release build url line [date]
  python3 "$GEN" --out "$1" ${2:+--history "$2"} --installer "$TMP_DIR/$3" \
    --release-name "$4" --build "$5" --url "$6" --sign-line "$7" \
    --date "${8:-Sat, 17 Oct 2026 12:00:00 GMT}"
}

# A first feed, from no history.
assert_ok 'writes a first feed' gen "$TMP_DIR/a.xml" '' Orthant-1.1.0-setup.exe 1.1.0 8 "$URL1" "$LINE1"
assert_ok 'it parses' python3 -c "import xml.etree.ElementTree as E; E.parse('$TMP_DIR/a.xml')"
check_first() {
  python3 - "$TMP_DIR/a.xml" "$URL1" "$SIG" <<'PY'
import sys, xml.etree.ElementTree as E
S = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = E.parse(sys.argv[1]).getroot().find('channel').findall('item')
assert len(items) == 1, len(items)
i = items[0]
assert i.find('title').text == '1.1.0'
assert i.find(S + 'version').text == '8'
assert i.find(S + 'shortVersionString').text == '1.1.0'
assert i.find(S + 'minimumSystemVersion').text == '10.0.17763'
e = i.find('enclosure').attrib
assert e['url'] == sys.argv[2]
assert e['length'] == '1000'
assert e['type'] == 'application/octet-stream'
assert e[S + 'os'] == 'windows-x64'
assert e[S + 'installerArguments'] == '/SILENT /SP- /NOCANCEL /SUPPRESSMSGBOXES /RELAUNCH=1'
assert e[S + 'edSignature'] == sys.argv[3]
PY
}
assert_ok 'the item carries what WinSparkle reads' check_first

# The next release keeps the first, newest first.
assert_ok 'writes the next feed over the first' gen "$TMP_DIR/b.xml" "$TMP_DIR/a.xml" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2"
check_second() {
  python3 - "$TMP_DIR/b.xml" "$URL1" "$URL2" <<'PY'
import sys, xml.etree.ElementTree as E
S = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = E.parse(sys.argv[1]).getroot().find('channel').findall('item')
assert [i.find(S + 'version').text for i in items] == ['9', '8']
assert [i.find('enclosure').get('url') for i in items] == [sys.argv[3], sys.argv[2]]
PY
}
assert_ok 'newest first, the earlier item kept' check_second
assert_ok 'an earlier item is written back exactly as it was' \
  bash -c "gen() { :; }; diff <(sed -n '/<item>/,/<\/item>/p' '$TMP_DIR/a.xml') <(sed -n '/<item>/,/<\/item>/p' '$TMP_DIR/b.xml' | tail -n \$(sed -n '/<item>/,/<\/item>/p' '$TMP_DIR/a.xml' | wc -l))"

# Refusals, each leaving no feed behind.
assert_fails 'refuses a build not above an earlier one' gen "$TMP_DIR/c.xml" "$TMP_DIR/b.xml" Orthant-1.1.0-setup.exe 1.1.0 9 "$URL1" "$LINE1"
assert_fails 'refuses a lower build' gen "$TMP_DIR/c.xml" "$TMP_DIR/b.xml" Orthant-1.1.0-setup.exe 1.1.0 7 "$URL1" "$LINE1"
assert_fails 'refuses a URL that names another file' gen "$TMP_DIR/c.xml" '' Orthant-1.1.0-setup.exe 1.1.0 8 "$URL2" "$LINE1"
assert_fails 'refuses a length that is not the file'"'"'s' gen "$TMP_DIR/c.xml" '' Orthant-1.1.0-setup.exe 1.1.0 8 "$URL1" "$LINE2"
assert_fails 'refuses a line that is not sign_update'"'"'s' gen "$TMP_DIR/c.xml" '' Orthant-1.1.0-setup.exe 1.1.0 8 "$URL1" 'length="1000"'
assert_fails 'refuses a signature of the wrong size' gen "$TMP_DIR/c.xml" '' Orthant-1.1.0-setup.exe 1.1.0 8 "$URL1" 'sparkle:edSignature="AAAA" length="1000"'
assert_fails 'refuses a build that is not a number' gen "$TMP_DIR/c.xml" '' Orthant-1.1.0-setup.exe 1.1.0 8a "$URL1" "$LINE1"
assert_fails 'refuses a release name that is not a version' gen "$TMP_DIR/c.xml" '' Orthant-1.1.0-setup.exe v1.1.0 8 "$URL1" "$LINE1"
sed 's#<sparkle:minimumSystemVersion>#<sparkle:releaseNotesLink>x</sparkle:releaseNotesLink><sparkle:minimumSystemVersion>#' "$TMP_DIR/a.xml" >"$TMP_DIR/unknown.xml"
assert_fails 'refuses history holding what it would drop' gen "$TMP_DIR/c.xml" "$TMP_DIR/unknown.xml" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2"
assert_fails 'refuses a history that names no file' gen "$TMP_DIR/c.xml" "$TMP_DIR/missing.xml" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2"
sed 's#<enclosure #<enclosure sparkle:dsaSignature="x" #' "$TMP_DIR/a.xml" >"$TMP_DIR/unknown-attr.xml"
assert_fails 'refuses history whose enclosure holds what it would drop' gen "$TMP_DIR/c.xml" "$TMP_DIR/unknown-attr.xml" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2"
sed 's#</enclosure>##; s#\(<enclosure [^>]*\)/>#\1/><enclosure url="x" length="1" type="t" sparkle:edSignature="'"$SIG"'"/>#' "$TMP_DIR/a.xml" >"$TMP_DIR/two-enclosures.xml"
assert_fails 'refuses history with two enclosures in an item' gen "$TMP_DIR/c.xml" "$TMP_DIR/two-enclosures.xml" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2"
sed 's#<title>1.1.0</title>#<title>1.1.0<b>x</b></title>#' "$TMP_DIR/a.xml" >"$TMP_DIR/nested.xml"
assert_fails 'refuses history with something nested in a field' gen "$TMP_DIR/c.xml" "$TMP_DIR/nested.xml" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2"
sed 's#<item>#<item id="x">#' "$TMP_DIR/a.xml" >"$TMP_DIR/item-attr.xml"
assert_fails 'refuses history with an attribute on an item' gen "$TMP_DIR/c.xml" "$TMP_DIR/item-attr.xml" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2"
sed 's#<title>1.1.0</title>#<title lang="en">1.1.0</title>#' "$TMP_DIR/a.xml" >"$TMP_DIR/field-attr.xml"
assert_fails 'refuses history with an attribute on a field' gen "$TMP_DIR/c.xml" "$TMP_DIR/field-attr.xml" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2"
# Refused for its own stated reason, not by a traceback.
refused() { # label history
  local err
  if err="$(gen "$TMP_DIR/c.xml" "$2" Orthant-1.2.0-beta.1-setup.exe 1.2.0-beta.1 9 "$URL2" "$LINE2" 2>&1 >/dev/null)"; then fail "$1 (unexpected success)"; return; fi
  case "$err" in *Traceback*) fail "$1 (a traceback)" ;; *'windows_appcast: '*) pass "$1" ;; *) fail "$1 ($err)" ;; esac
}
sed 's#<pubDate>[^<]*</pubDate>##' "$TMP_DIR/a.xml" >"$TMP_DIR/no-date.xml"
refused 'refuses history with an item missing a field' "$TMP_DIR/no-date.xml"
sed 's#<enclosure [^>]*/>##' "$TMP_DIR/a.xml" >"$TMP_DIR/no-enclosure.xml"
refused 'refuses history with an item missing its enclosure' "$TMP_DIR/no-enclosure.xml"
malformed() {
  local err
  err="$(gen "$TMP_DIR/c.xml" '' Orthant-1.1.0-setup.exe 1.1.0 8 "$URL1" 'sparkle:edSignature="AAAAA" length="1000"' 2>&1 >/dev/null)" && return 1
  case "$err" in *Traceback*) return 1 ;; *'windows_appcast: '*) return 0 ;; *) return 1 ;; esac
}
assert_ok 'refuses a signature that is not base64, saying so' malformed
if [ -e "$TMP_DIR/c.xml" ] || [ -e "$TMP_DIR/c.xml.partial" ]; then fail 'a refusal wrote a feed'; else pass 'no refusal wrote a feed'; fi

printf '%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
