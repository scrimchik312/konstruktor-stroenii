import 'package:shared_preferences/shared_preferences.dart';

import '../models/organization_settings.dart';
import '../models/user_mode.dart';

/// Хранилище глобальных настроек приложения.
///
/// Хранит выбранный режим (клиент / проектировщик), флаг подсказок и
/// реквизиты организации, подставляемые в штамп чертежей.
class SettingsRepository {
  static const _modeKey = 'user_mode';
  static const _hintsEnabledKey = 'hints_enabled';
  static const _organizationKey = 'organization_settings_v1';

  final SharedPreferences _prefs;

  SettingsRepository(this._prefs);

  static Future<SettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsRepository(prefs);
  }

  /// Возвращает выбранный пользователем режим. `null`, если пользователь
  /// ещё не делал выбор — в этом случае показываем экран первого запуска.
  UserMode? loadMode() {
    final raw = _prefs.getString(_modeKey);
    if (raw == null) return null;
    return UserMode.fromName(raw);
  }

  Future<void> saveMode(UserMode mode) async {
    await _prefs.setString(_modeKey, mode.name);
  }

  /// Включён ли автопоказ обучающих подсказок. По умолчанию — да: новый
  /// пользователь получает «экскурсию» по каждому экрану. Сохранённое
  /// `false` означает «пользователь сам отключил» — больше не подсказывать
  /// автоматически, но кнопка «?» в AppBar остаётся доступной.
  bool loadHintsEnabled() {
    return _prefs.getBool(_hintsEnabledKey) ?? true;
  }

  Future<void> saveHintsEnabled(bool value) async {
    await _prefs.setBool(_hintsEnabledKey, value);
  }

  /// Возвращает сохранённые реквизиты организации. Если пользователь их
  /// ещё не задавал — возвращает пустой объект (штамп подставит дефолт
  /// «Конструктор строений»).
  OrganizationSettings loadOrganization() {
    final raw = _prefs.getString(_organizationKey);
    if (raw == null) return const OrganizationSettings();
    return OrganizationSettings.tryDecode(raw) ??
        const OrganizationSettings();
  }

  Future<void> saveOrganization(OrganizationSettings value) async {
    await _prefs.setString(_organizationKey, value.encode());
  }
}
