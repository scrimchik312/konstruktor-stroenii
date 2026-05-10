import 'package:flutter/foundation.dart';

/// Миграции схемы хранения проектов в SharedPreferences.
///
/// Работают на уровне сырого JSON (`Map<String, dynamic>`), **до** парсинга
/// в [HouseProject], потому что в миграциях часто нужно переименовывать
/// или удалять поля, которых уже нет в актуальной модели Dart‑классов.
///
/// **Как добавлять новую миграцию:**
/// 1. В [ProjectRepository.currentSchemaVersion] инкрементировать число.
/// 2. В этом файле добавить функцию `_migrateVN_VM` и зарегистрировать её
///    в [_migrations] под ключом `versionFrom`.
/// 3. Написать unit‑тест на новую миграцию в `test/project_migrations_test.dart`.
///
/// **Принцип «вверх и только вверх»:** пользовательские данные мигрируют
/// только в сторону более новой схемы. Если пользователь зайдёт со старой
/// версии приложения после новой — это его проблема (и наш баг релиза).
class ProjectMigrations {
  ProjectMigrations._();

  /// Цепочка миграций: ключ — стартовая версия, значение — функция,
  /// поднимающая JSON на следующую версию (на одну ступень вверх).
  static final Map<int, _Migrator> _migrations = <int, _Migrator>{
    1: _migrateV1ToV2,
    // 2: _migrateV2ToV3,  ← добавится при изменении модели под фундамент
  };

  /// Поднять список сырых JSON‑проектов с версии [fromVersion] до версии
  /// [toVersion]. Если [fromVersion] >= [toVersion] — список возвращается
  /// без изменений (пользователь либо уже на актуальной схеме, либо как‑то
  /// оказался на более новой — не будем ломать).
  static List<Map<String, dynamic>> migrate({
    required List<Map<String, dynamic>> projects,
    required int fromVersion,
    required int toVersion,
  }) {
    if (fromVersion >= toVersion) return projects;

    var current = projects;
    var version = fromVersion;
    while (version < toVersion) {
      final step = _migrations[version];
      if (step == null) {
        // Должно ловиться юнит‑тестом, но защитимся в рантайме.
        debugPrint('ProjectMigrations: нет миграции с v$version, '
            'останавливаемся');
        break;
      }
      current = current.map(step).toList();
      version += 1;
    }
    return current;
  }

  /// **v1 → v2:** введение поля `schema_version` на уровне обёртки.
  ///
  /// На уровне отдельного проекта изменений нет — это первая миграция,
  /// которая просто фиксирует факт перехода на формат с обёрткой.
  /// Никакие поля внутри проекта не трогаем.
  static Map<String, dynamic> _migrateV1ToV2(Map<String, dynamic> project) {
    return project;
  }
}

typedef _Migrator = Map<String, dynamic> Function(Map<String, dynamic> project);
