/// The major version in macOS's own version string, or null when [text] is not
/// one.
///
/// `Platform.operatingSystemVersion` on a Mac reads `Version 15.1 (Build
/// 24B83)`. Only the shape macOS uses is read, so a Windows string or a bare
/// number is unknown rather than guessed: a wrong guess names the wrong System
/// Settings pane, and an unknown version is the caller's to default.
int? macOSMajorVersion(String text) {
  final match = RegExp(r'^\s*Version\s+(\d+)\b').firstMatch(text);
  return match == null ? null : int.parse(match.group(1)!);
}
