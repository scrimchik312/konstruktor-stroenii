// Phase-3b §17.2.1 — миграция сериализации `HouseProject`.
//
// Проверяем, что:
//   1. Старые JSON-проекты (без поля `architectureFootprint`)
//      десериализуются без ошибок.
//   2. `effectiveArchitectureFootprint` для старого проекта возвращает
//      прямоугольник `brief.footprintWidth × brief.footprintLength`.
//   3. Новые JSON-проекты с `architectureFootprint` сохраняются и
//      восстанавливаются (JSON-roundtrip).

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/models/building_footprint.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/house_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Старый JSON без architectureFootprint десериализуется (миграция)', () {
    // Минимальный валидный legacy JSON v64.x.
    final legacy = {
      'id': 'legacy-1',
      'name': 'Старый проект',
      'constructionType': 'privateHouse',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'brief': {
        'footprintWidth': 12.0,
        'footprintLength': 9.0,
        'floors': 1,
      },
      'foundation': <String, dynamic>{},
      'walls': <String, dynamic>{},
      'floorSlabs': <String, dynamic>{},
      'roof': <String, dynamic>{},
      'staircase': <String, dynamic>{},
      'drawings': {'drawings': <Map<String, dynamic>>[]},
    };

    final project = HouseProject.fromJson(
      Map<String, dynamic>.from(legacy),
    );
    expect(project.architectureFootprint, isNull,
        reason: 'Legacy JSON не должен содержать footprint.');
    final eff = project.effectiveArchitectureFootprint;
    expect(eff.area, closeTo(12.0 * 9.0, 1e-6));
    expect(eff.bbox.width, closeTo(12.0, 1e-6));
    expect(eff.bbox.height, closeTo(9.0, 1e-6));
  });

  test('Новый JSON c architectureFootprint roundtrip', () {
    final brief = ClientBrief(
      footprintWidth: 10,
      footprintLength: 10,
      floors: 1,
    );
    final original = HouseProject(
      id: 'fp-test',
      name: 'L-проект',
      constructionType: ConstructionType.privateHouse,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
      brief: brief,
      architectureFootprint: BuildingFootprint.lShape(
        width: 10,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ),
    );

    final restored = HouseProject.fromJson(
      Map<String, dynamic>.from(original.toJson()),
    );
    expect(restored.architectureFootprint, isNotNull);
    expect(restored.effectiveArchitectureFootprint.area, closeTo(84.0, 1e-6));
    expect(restored.effectiveArchitectureFootprint.outline.length, 6);
  });

  test('effectiveArchitectureFootprint фолбэк для проекта без brief', () {
    // Проект с нулевыми footprintWidth/Length — фолбэк на 10x8.
    final empty = HouseProject(
      id: 'empty',
      name: '—',
      constructionType: ConstructionType.privateHouse,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final fp = empty.effectiveArchitectureFootprint;
    expect(fp.area, greaterThan(0));
  });
}
