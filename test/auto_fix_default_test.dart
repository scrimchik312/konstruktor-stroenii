// v68 §24.7: regression-тест на «молчаливый» auto-rollback мебели
// при регенерации чертежей.
//
// До v68: `regenerateDrawings(...)` по умолчанию пропускал autoFix
// и пользователь видел warning «Этаж 1: «N. Комната» недоступна»
// до тех пор, пока вручную не нажмёт кнопку «Исправить».
//
// После v68: autoFix=true по умолчанию. `_autoFixPlans` молча убирает
// мебель, перекрывающую дверные зоны (< 0.9 м), и предупреждения о
// недостижимости в массив `project.warnings` не попадают.

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/wall_materials.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/drawings_collection.dart';
import 'package:construction_calculator/models/foundation.dart';
import 'package:construction_calculator/models/foundation_design.dart';
import 'package:construction_calculator/models/house_project.dart';
import 'package:construction_calculator/models/roof_design.dart';
import 'package:construction_calculator/models/staircase_design.dart';
import 'package:construction_calculator/models/user_mode.dart';
import 'package:construction_calculator/models/walls_design.dart';
import 'package:construction_calculator/services/drawing_generator.dart';

void main() {
  HouseProject _newProject() {
    final now = DateTime.now();
    final brief = ClientBrief(
      snowZone: 4,
      windZone: 'II',
      footprintWidth: 12,
      footprintLength: 9,
      floors: 1,
      hasGarage: false,
      hasTerrace: false,
      hasMansard: false,
      wallMaterial: WallMaterial.aerated,
    );
    return HouseProject(
      id: 'p-autofix',
      name: 'Auto-fix test',
      constructionType: ConstructionType.privateHouse,
      createdAt: now,
      updatedAt: now,
      drawings: DrawingsCollection(drawings: []),
      brief: brief,
      walls: WallsDesign(material: 'aerated', thickness: 400, height: 2.8),
      roof: RoofDesign(
        type: 'gable',
        slopeAngle: 30,
        roofingMaterial: 'metal_tile',
      ),
      foundation: FoundationDesign(type: FoundationType.strip),
      staircase: StaircaseDesign(floorHeight: 2.8),
    );
  }

  test('autoFix=true (по умолчанию): warnings не накапливаются после '
      'регенерации', () {
    final project = _newProject();
    project.warnings.add('Этаж 1: «1. Комната» недоступна — стартовое '
        'предупреждение');
    // Имитация: была регенерация со старым autoFix=false; warning
    // остался. Регенерируем заново с дефолтным autoFix=true →
    // предупреждения должны быть очищены / не возникнуть заново.
    DrawingGenerator.generate(
      project: project,
      mode: UserMode.designer,
      autoFix: true,
    );
    // Условие: после autoFix не должно быть warnings вида «Этаж … недоступна».
    final hasFloorWarning =
        project.warnings.any((w) => w.startsWith('Этаж '));
    expect(hasFloorWarning, isFalse,
        reason: 'autoFix должен молчаливо убрать мебель, блокирующую '
            'проходы — warnings про недоступность не должны возникать.');
  });

  test('autoFix=false: warnings возможны (старая семантика)', () {
    final project = _newProject();
    DrawingGenerator.generate(
      project: project,
      mode: UserMode.designer,
      autoFix: false,
    );
    // Не утверждаем, что warning ОБЯЗАТЕЛЬНО есть — на стандартном
    // 12×9 м плане часто всё нормально. Утверждаем, что код
    // отрабатывает без падений (smoke).
    expect(project.warnings, isA<List<String>>());
  });
}
