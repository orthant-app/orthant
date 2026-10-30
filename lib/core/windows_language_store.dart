import 'windows_registry.dart';

/// Where Orthant keeps its own general settings, beside the updater's
/// ([kUpdateSettingsPath] in `windows_updater.dart`), under `HKEY_CURRENT_USER`.
/// The uninstaller deletes `Software\Orthant` with everything in it.
const kLanguageSettingsPath = r'Software\Orthant\Orthant\Settings';

/// The `REG_SZ` value under [kLanguageSettingsPath] holding the language
/// choice: a BCP-47 tag, deleted for System.
const kLanguageValue = 'Language';

/// The language the user chose for Orthant, kept where the platform has no
/// per-app language setting of its own (Windows). Never throws: a value that
/// cannot be read reads as absent.
abstract class LanguageStore {
  /// The stored tag as it is, whatever it holds; null when none is stored.
  String? read();

  /// Stores [tag], or removes the stored choice for null (System).
  void write(String? tag);
}

/// [LanguageStore] in the current user's hive. Windows only.
class RegistryLanguageStore implements LanguageStore {
  const RegistryLanguageStore();

  @override
  String? read() => readUserString(kLanguageSettingsPath, kLanguageValue);

  @override
  void write(String? tag) {
    if (tag == null) {
      deleteUserValue(kLanguageSettingsPath, kLanguageValue);
    } else {
      writeUserString(kLanguageSettingsPath, kLanguageValue, tag);
    }
  }
}
