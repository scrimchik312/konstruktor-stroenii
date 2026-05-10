import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/house_project.dart';
import 'project_migrations.dart';

/// Хранилище проектов на диске.
///
/// Используем [SharedPreferences] как универсальный ключ-значение бэкенд:
/// на вебе он пишет в localStorage, на десктопе — в файл, на мобильных —
/// в нативные настройки. Все проекты сериализуются в JSON и хранятся под
/// одним ключом — для текущих объёмов (десятки проектов) этого достаточно.
///
/// **Схема хранения с версионированием (v2+):**
/// ```json
/// {
///   "schema_version": 2,
///   "projects": [ {...}, {...} ]
/// }
/// ```
///
/// Старый плоский массив (v1) тоже распознаётся и автоматически
/// мигрируется при первом чтении. Это критично: без миграций любое
/// расширение [HouseProject] на новые поля (например, расчёт фундамента)
/// сломает чтение старых проектов и пользователь молча потеряет всё, что
/// сохранил. См. [ProjectMigrations].
class ProjectRepository {
  /// Текущая версия схемы хранения. **Инкрементировать при каждом
  /// несовместимом изменении** в [HouseProject.toJson] и одновременно
  /// добавлять новую миграцию в [ProjectMigrations].
  static const int currentSchemaVersion = 2;

  static const _key = 'projects.v1';

  final SharedPreferences _prefs;

  ProjectRepository(this._prefs);

  static Future<ProjectRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return ProjectRepository(prefs);
  }

  /// Прочитать проекты с диска. Если данные на старой версии схемы —
  /// прогнать через миграции и сохранить обратно.
  ///
  /// На любой ошибке десериализации — возвращаем пустой список и пишем
  /// в `debugPrint`. Раньше тут был молчаливый `try/catch return []` —
  /// клиент терял проекты без предупреждения. Теперь хотя бы видно
  /// диагностику в консоли разработчика.
  List<HouseProject> loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);

      // Текущий формат: {schema_version, projects}.
      // Совместимость: чистый List — это формат v1.
      final List<dynamic> rawProjects;
      final int version;
      if (decoded is List) {
        version = 1;
        rawProjects = decoded;
      } else if (decoded is Map<String, dynamic>) {
        version = (decoded['schema_version'] as int?) ?? 1;
        rawProjects = decoded['projects'] as List<dynamic>? ?? const [];
      } else {
        debugPrint('ProjectRepository: unexpected JSON root '
            '${decoded.runtimeType} — пропускаем загрузку');
        return [];
      }

      // Миграции до текущей версии — сначала на уровне сырого JSON,
      // только потом парсим в модели. Это позволяет в миграциях
      // переименовывать/удалять поля без падения [HouseProject.fromJson].
      final migrated = ProjectMigrations.migrate(
        projects: rawProjects.whereType<Map<String, dynamic>>().toList(),
        fromVersion: version,
        toVersion: currentSchemaVersion,
      );

      final parsed = <HouseProject>[];
      for (final json in migrated) {
        try {
          parsed.add(HouseProject.fromJson(json));
        } catch (e, st) {
          // Один битый проект не должен валить остальные.
          debugPrint('ProjectRepository: пропускаю битый проект: $e\n$st');
        }
      }

      // Если применили миграцию — сразу пересохраняем в новом формате,
      // чтобы при следующей загрузке не прогонять миграции снова и не
      // оставлять старый формат в localStorage пользователя.
      if (version != currentSchemaVersion) {
        // ignore: discarded_futures
        saveAll(parsed);
      }
      return parsed;
    } catch (e, st) {
      debugPrint('ProjectRepository: не смог прочитать projects: $e\n$st');
      return [];
    }
  }

  Future<void> saveAll(List<HouseProject> projects) async {
    final payload = <String, dynamic>{
      'schema_version': currentSchemaVersion,
      'projects': projects.map((p) => p.toJson()).toList(),
    };
    await _prefs.setString(_key, jsonEncode(payload));
  }
}
