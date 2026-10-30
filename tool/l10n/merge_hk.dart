// Writes lib/l10n/app_zh_Hant_HK.arb: the Traditional Chinese file with the
// Hong Kong overrides laid over it.
//
// gen-l10n makes every locale variant subclass the bare-language class, so a
// sparse zh_Hant_HK file would inherit Simplified Chinese. Hong Kong therefore
// ships a complete file, and this is the only thing that writes it:
// test/l10n/arb_test.dart fails if the file is anything but this merge.
//
//   dart run tool/l10n/merge_hk.dart && flutter gen-l10n
import 'dart:convert';
import 'dart:io';

/// [zhHant] with `@@locale` set to `zh_Hant_HK` and the value of each key in
/// [overrides] replaced. Neither argument is modified.
Map<String, dynamic> mergeHongKong(
  Map<String, dynamic> zhHant,
  Map<String, dynamic> overrides,
) {
  final merged = Map<String, dynamic>.of(zhHant);
  merged['@@locale'] = 'zh_Hant_HK';
  for (final entry in overrides.entries) {
    merged[entry.key] = entry.value;
  }
  return merged;
}

void main() {
  // tool/l10n/merge_hk.dart -> the repository root, wherever this is run from.
  final root = File.fromUri(Platform.script).parent.parent.parent.path;
  Map<String, dynamic> read(String name) =>
      jsonDecode(File('$root/lib/l10n/$name').readAsStringSync())
          as Map<String, dynamic>;

  final merged =
      mergeHongKong(read('app_zh_Hant.arb'), read('zh_Hant_HK.overrides.json'));
  File('$root/lib/l10n/app_zh_Hant_HK.arb').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(merged)}\n');
}
