import 'dart:ffi';
import 'dart:ui' show Locale;

import 'package:ffi/ffi.dart';

// The OS's preferred display languages on Windows, asked of Windows itself.
//
// Never from `PlatformDispatcher.instance.locales`: the embedder runs the
// engine, then sends the system locales (`FlutterWindowsEngine::Run`, then
// `SendSystemLocales`), and the root isolate sees that message only once
// `main()` has reached its first `await`. Everything Orthant needs at launch
// (the updater's language, the first window's) is read before that, and would
// see an empty list, so a System user on Chinese Windows got English
// everywhere. Nor `Platform.localeName`, which is the regional format, not the
// display language.
//
// So this makes the embedder's own call and parses it as the embedder does
// (`system_utils.cc`: `GetPreferredLanguagesFromMUI`, `GetPreferredLanguages`,
// `ParseLanguageName`), which keeps the answer the same list the dispatcher
// holds from its first frame on. One source feeds both the updater's language
// and `WindowController.systemLocales`.

/// `MUI_LANGUAGE_NAME | MUI_UI_FALLBACK` of winnls.h, the flags the embedder
/// passes: names such as `zh-TW` (not ids), the user's preferred languages
/// with the system's fallbacks merged in. `MUI_LANGUAGE_NAME` is 0x8;
/// `MUI_UI_FALLBACK` is `MUI_MERGE_SYSTEM_FALLBACK` (0x10) with
/// `MUI_MERGE_USER_FALLBACK` (0x20).
const _flags = 0x8 | 0x10 | 0x20;

typedef _GetLanguagesNative = Int32 Function(Uint32 flags,
    Pointer<Uint32> count, Pointer<Uint16> buffer, Pointer<Uint32> length);
typedef _GetLanguagesDart = int Function(int flags, Pointer<Uint32> count,
    Pointer<Uint16> buffer, Pointer<Uint32> length);

/// The languages in a double-NUL-terminated multi-string, in order: each is
/// ended by a NUL and the list by an empty one, as `GetThreadPreferredUILanguages`
/// writes it. Whatever follows the list's end is ignored, and a last language
/// with no NUL (a buffer cut short) is kept.
List<String> splitMultiString(String buffer) {
  final languages = <String>[];
  var start = 0;
  while (start < buffer.length && buffer[start] != '\u0000') {
    var end = buffer.indexOf('\u0000', start);
    if (end == -1) end = buffer.length;
    languages.add(buffer.substring(start, end));
    start = end + 1;
  }
  return languages;
}

/// The locale a Windows language name stands for, split as the embedder
/// splits it: on `-`, dropping `x` and what follows (private use); three
/// parts are language, script and region; two are language and a script when
/// the second is four letters long and a region otherwise; one is the
/// language alone. Windows' own names for Chinese carry no script
/// (`zh-TW` is `Locale('zh', 'TW')`), and the resolver takes it from the
/// region. Null for a name with no language.
Locale? parsePreferredLanguage(String name) {
  final parts = <String>[];
  for (final part in name.split('-')) {
    if (part == 'x') break;
    parts.add(part);
  }
  if (parts.isEmpty || parts.first.isEmpty) return null;
  String? script;
  String? region;
  if (parts.length == 3) {
    script = parts[1];
    region = parts[2];
  } else if (parts.length == 2) {
    if (parts[1].length == 4) {
      script = parts[1];
    } else {
      region = parts[1];
    }
  }
  return Locale.fromSubtags(
    languageCode: parts.first,
    scriptCode: script == null || script.isEmpty ? null : script,
    countryCode: region == null || region.isEmpty ? null : region,
  );
}

/// [parsePreferredLanguage] of each of [names], in order, without those that
/// name no language.
List<Locale> parsePreferredLanguages(Iterable<String> names) => [
      for (final name in names) ?parsePreferredLanguage(name),
    ];

/// The language names `GetThreadPreferredUILanguages` returns for this thread,
/// most preferred first (`zh-TW`, `en-US`); empty when Windows says nothing.
/// Windows only.
List<String> readPreferredLanguageNames() {
  final get = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<_GetLanguagesNative, _GetLanguagesDart>(
          'GetThreadPreferredUILanguages');
  final count = calloc<Uint32>();
  final length = calloc<Uint32>();
  Pointer<Uint16>? buffer;
  try {
    // Once for the size in characters, once for the list, as the embedder does.
    if (get(_flags, count, nullptr, length) == 0 || length.value == 0) {
      return const [];
    }
    buffer = calloc<Uint16>(length.value);
    if (get(_flags, count, buffer, length) == 0) return const [];
    return splitMultiString(
        String.fromCharCodes(buffer.asTypedList(length.value)));
  } finally {
    if (buffer != null) calloc.free(buffer);
    calloc.free(length);
    calloc.free(count);
  }
}

/// The OS's preferred display languages, most preferred first, ignoring any
/// choice made in Orthant. Windows only. Never throws: a read that fails is
/// "the OS did not say" (the resolver then falls back to English), not a
/// launch that stops.
List<Locale> readSystemLocales() {
  try {
    return parsePreferredLanguages(readPreferredLanguageNames());
  } catch (_) {
    return const [];
  }
}
