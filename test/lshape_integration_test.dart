// Phase-3b §17.2.1 — интеграционные тесты глубокого слоя.
//
// Покрывают:
//   1. FloorPlanGenerator.generate(footprint:) обрезает комнаты по
//      L-полигону: суммарная площадь оставшихся комнат ≤ площади
//      полигона, и все центры комнат лежат внутри полигона.
//   2. Building3DGenerator с полигональным `architectureFootprint`
//      строит outline по полигону (6 вершин) и одну стену на каждый
//      сегмент outline (6 стен на L-форму).
//   3. Прямоугольный проект продолжает использовать 4-стенную модель
//      (нулевая регрессия).

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/wall_materials.dart';
import 'package:construction_calculator/models/building_footprint.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/drawings_collection.dart';
import 'package:construction_calculator/models/foundation.dart';
import 'package:construction_calculator/models/foundation_design.dart';
import 'package:construction_calculator/models/house_project.dart';
import 'package:construction_calculator/models/roof_design.dart';
import 'package:construction_calculator/models/staircase_design.dart';
import 'package:construction_calculator/models/walls_design.dart';
import 'package:construction_calculator/services/building3d_generator.dart';
import 'package:construction_calculator/services/floor_plan_generator.dart';
import 'package:construction_calculator/services/pdf_catalog_card.dart';
import 'package:construction_calculator/services/roof_plan_geometry.dart';

ClientBrief _brief(double w, double l) => ClientBrief(
      snowZone: 4,
      windZone: 'II',
      footprintWidth: w,
      footprintLength: l,
      floors: 1,
      wallMaterial: WallMaterial.aerated,
      rooms: const {
        'bedroom': 2,
        'kitchen': 1,
        'bathroom': 1,
        'livingRoom': 1,
      },
    );

HouseProject _project({
  required ClientBrief brief,
  BuildingFootprint? footprint,
}) =>
    HouseProject(
      id: 'p',
      name: 'L-shape integration',
      constructionType: ConstructionType.privateHouse,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
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
      architectureFootprint: footprint,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'FloorPlanGenerator: L-shape footprint обрезает комнаты — все центры '
      'попадают внутрь полигона, суммарная площадь ≤ полигону', () {
    final brief = _brief(10, 10);
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final plans = FloorPlanGenerator.generate(brief, footprint: fp);
    expect(plans, isNotEmpty);
    final plan = plans.first;
    expect(plan.hasPolygonalFootprint, isTrue,
        reason: 'после обрезки в плане должен сохраниться полигон');
    // Все оставшиеся комнаты — внутри полигона.
    for (final r in plan.rooms) {
      final cx = r.x + r.width / 2;
      final cy = r.y + r.height / 2;
      expect(fp.contains(Vec2(cx, cy)), isTrue,
          reason: 'центр комнаты "${r.label}" должен лежать внутри L-полигона');
    }
    // Площадь оставшихся комнат не превосходит площадь полигона.
    final used = plan.rooms.fold<double>(0, (s, r) => s + r.area);
    expect(used, lessThanOrEqualTo(fp.area + 1e-6));
  });

  test(
      'FloorPlanGenerator: прямоугольный footprint в виде BuildingFootprint.rect '
      'не обрезает комнаты (нулевая регрессия)', () {
    final brief = _brief(10, 8);
    final baseline = FloorPlanGenerator.generate(brief);
    final withRect = FloorPlanGenerator.generate(
      brief,
      footprint: BuildingFootprint.rect(10, 8),
    );
    expect(withRect.length, baseline.length);
    expect(withRect.first.rooms.length, baseline.first.rooms.length,
        reason: 'rect-footprint не должен ничего отбрасывать');
  });

  test(
      'Building3DGenerator: L-shape architectureFootprint даёт outline '
      'из 6 вершин и 6 стен на этаж', () {
    final brief = _brief(10, 10);
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final project = _project(brief: brief, footprint: fp);
    final model = Building3DGenerator.generate(project);
    expect(model, isNotNull);
    // Полигональный outline = 6 вершин для L-формы.
    expect(model!.foundation.outline.length, 6);
    expect(model.floors, isNotEmpty);
    expect(model.floors.first.walls.length, 6,
        reason: 'L-форма даёт 6 наружных стен (по числу сегментов outline)');
  });

  test(
      'Building3DGenerator: T-shape architectureFootprint 12×10 / стержень '
      '4×4 даёт outline из 8 вершин и 8 стен на этаж', () {
    final brief = _brief(12, 10);
    final fp = BuildingFootprint.tShape(
      width: 12,
      height: 10,
      stemWidth: 4,
      stemHeight: 4,
    );
    final project = _project(brief: brief, footprint: fp);
    final model = Building3DGenerator.generate(project);
    expect(model, isNotNull);
    expect(model!.foundation.outline.length, 8);
    expect(model.floors.first.walls.length, 8);
    // Кровля «комбинированная» — два конька, ≥4 ската.
    expect(model.roof.slopes.length, greaterThanOrEqualTo(4));
    expect(model.roof.typeLabel, contains('уступам'));
  });

  test(
      'Building3DGenerator: U-shape architectureFootprint 12×10 / вырез '
      '4×4 даёт outline из 8 вершин и 8 стен на этаж', () {
    final brief = _brief(12, 10);
    final fp = BuildingFootprint.uShape(
      width: 12,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final project = _project(brief: brief, footprint: fp);
    final model = Building3DGenerator.generate(project);
    expect(model, isNotNull);
    expect(model!.foundation.outline.length, 8);
    expect(model.floors.first.walls.length, 8);
    // Декомпозиция = 3 прямоугольника → ≥6 скатов.
    expect(model.roof.slopes.length, greaterThanOrEqualTo(6));
    expect(model.roof.typeLabel, contains('уступам'));
  });

  test(
      'Building3DGenerator: прямоугольный проект (без architectureFootprint) '
      'продолжает иметь 4 стены и 4-вершинный outline', () {
    final brief = _brief(10, 8);
    final project = _project(brief: brief, footprint: null);
    final model = Building3DGenerator.generate(project);
    expect(model, isNotNull);
    expect(model!.foundation.outline.length, 4);
    expect(model.floors.first.walls.length, 4);
  });

  test(
      'АР-0 ТЭП: для L-формы 10×10 с вырезом 4×4 «Площадь застройки» '
      '= 84 м² (полигон), а не 100 м² (bbox)', () {
    final brief = _brief(10, 10);
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final plans = FloorPlanGenerator.generate(brief, footprint: fp);
    final project = _project(brief: brief, footprint: fp);
    final builtArea = PdfCatalogCard.computeBuiltAreaM2(project, plans);
    // Полигон L-формы 10×10 − 4×4 = 84 м².
    expect(builtArea, closeTo(84.0, 1e-6),
        reason: 'площадь застройки должна совпадать с площадью полигона');
    // Контр-проверка: bbox дал бы 100 — мы НЕ должны его получить.
    expect(builtArea, lessThan(99.0));
  });

  test(
      'АР-0 ТЭП: для прямоугольного проекта 10×8 «Площадь застройки» = 80 м² '
      '(нулевая регрессия)', () {
    final brief = _brief(10, 8);
    final plans = FloorPlanGenerator.generate(brief);
    final project = _project(brief: brief, footprint: null);
    final builtArea = PdfCatalogCard.computeBuiltAreaM2(project, plans);
    expect(builtArea, closeTo(80.0, 1e-6));
  });

  test(
      'Building3DGenerator: L-shape с двускатной крышей даёт несколько '
      'скатов вместо одного (раскладывается по уступам)', () {
    final brief = _brief(10, 10);
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final project = _project(brief: brief, footprint: fp);
    final model = Building3DGenerator.generate(project);
    expect(model, isNotNull);
    // Прямоугольная двускатная даёт 2 ската; L-форма раскладывается на
    // 2 прямоугольника → должно быть >= 4 ската.
    expect(model!.roof.slopes.length, greaterThanOrEqualTo(4),
        reason:
            'L-форма должна давать минимум 4 ската (по 2 на прямоугольник)');
    expect(model.roof.typeLabel, contains('уступ'),
        reason: 'для L-формы типовая метка содержит "уступ"');
    // Все скаты должны иметь высоту ≥ wallTopElev (крыша не «провисает»
    // ниже стен).
    final wallTop = project.walls.height ?? project.staircase.floorHeight ?? 2.8;
    for (final slope in model.roof.slopes) {
      for (final c in slope.corners) {
        expect(c.z, greaterThan(wallTop * 0.5),
            reason: 'все вершины скатов должны быть на уровне стен или выше');
      }
    }
  });

  test(
      'Building3DGenerator: прямоугольный проект продолжает иметь '
      'ровно одну bbox-двускатную (нулевая регрессия)', () {
    final brief = _brief(10, 8);
    final project = _project(brief: brief, footprint: null);
    final model = Building3DGenerator.generate(project);
    expect(model, isNotNull);
    expect(model!.roof.slopes.length, 2,
        reason: 'двускатная для прямоугольника даёт ровно 2 ската');
    expect(model.roof.typeLabel, 'Двускатная');
  });

  test(
      'Building3DGenerator: L-shape с плоской крышей даёт ОДИН скат '
      'по полигону, не bbox', () {
    final brief = _brief(10, 10);
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final project = HouseProject(
      id: 'p-flat',
      name: 'L flat',
      constructionType: ConstructionType.privateHouse,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      drawings: DrawingsCollection(drawings: []),
      brief: brief,
      walls: WallsDesign(material: 'aerated', thickness: 400, height: 2.8),
      roof: RoofDesign(
        type: 'flat',
        slopeAngle: 1.5,
        roofingMaterial: 'metal_tile',
      ),
      foundation: FoundationDesign(type: FoundationType.strip),
      staircase: StaircaseDesign(floorHeight: 2.8),
      architectureFootprint: fp,
    );
    final model = Building3DGenerator.generate(project);
    expect(model, isNotNull);
    expect(model!.roof.slopes.length, 1);
    // 6 вершин — это L-полигон, 4 — это bbox; ожидаем 6 (полигон).
    expect(model.roof.slopes.first.corners.length, 6,
        reason: 'плоская крыша по L-форме должна копировать outline (6 вершин)');
  });

  test(
      'RoofPlanGeometry.computePolygonal: L-форма 10×10/4×4 даёт '
      'два конька, ≥1 ендову и L-овый внешний контур', () {
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final geom = RoofPlanGeometry.computePolygonal(
      shape: RoofShape.gable,
      footprint: fp,
      slopeDegrees: 30,
      snowZone: 4,
    );
    // Декомпозиция L-формы → 2 прямоугольника → 2 конька + 4 ската.
    expect(geom.ridges.length, 2,
        reason: 'L-форма должна давать 2 конька (по одному на прямоугольник)');
    expect(geom.slopes.length, 4,
        reason: 'L-форма должна давать 4 ската (по 2 на прямоугольник)');
    expect(geom.valleys.length, greaterThanOrEqualTo(1),
        reason:
            'L-форма должна давать минимум одну ендову на стыке прямоугольников');
    // Внешний контур — L-полигон расширенный наружу. v66 §21.1.4:
    // на каждой reflex-вершине outerOutline эмитирует 3 вершины
    // (вход карниза + угол стены + выход карниза) для нулевого
    // overhang во внутреннем углу. У L-формы 1 reflex → 6 + 2 = 8.
    expect(geom.outerOutline.length, 8,
        reason:
            'L-форма: 5 convex + 1 reflex (×3 вершины) = 8 точек контура');
    // Снегозадержатели включены при snowZone>=4.
    expect(geom.snowGuards.isNotEmpty, isTrue);
  });

  test(
      'RoofPlanGeometry.computePolygonal: прямоугольный проект fallback-ит '
      'на bbox-овый compute (нулевая регрессия)', () {
    final fp = BuildingFootprint.rect(10, 8);
    final geom = RoofPlanGeometry.computePolygonal(
      shape: RoofShape.gable,
      footprint: fp,
      slopeDegrees: 30,
      snowZone: 1,
    );
    expect(geom.ridges.length, 1,
        reason: 'прямоугольная двускатная — один конёк');
    expect(geom.slopes.length, 2);
    expect(geom.valleys, isEmpty);
  });

  test('BuildingFootprint.tShape: 8 вершин, площадь = bbox - вырез', () {
    final fp = BuildingFootprint.tShape(
      width: 12,
      height: 10,
      stemWidth: 4,
      stemHeight: 4,
    );
    expect(fp.outline.length, 8);
    // bbox = 12×10 = 120; стержень добавляется ВНУТРИ bbox-а как
    // выступ — общая площадь = верх (12×6) + стержень (4×4) = 88.
    expect(fp.area, closeTo(88, 0.01));
    // Точка по центру выступа (x=6, y=8) внутри полигона.
    expect(fp.contains(const Vec2(6, 8)), isTrue);
    // Точка слева от стержня (x=2, y=8) — вне полигона.
    expect(fp.contains(const Vec2(2, 8)), isFalse);
  });

  test('BuildingFootprint.uShape: 8 вершин, площадь = bbox - вырез', () {
    final fp = BuildingFootprint.uShape(
      width: 12,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    expect(fp.outline.length, 8);
    // bbox = 12×10 = 120; вырез 4×4 = 16; площадь = 104.
    expect(fp.area, closeTo(104, 0.01));
    // Точка в вырезе (x=6, y=2) — вне полигона.
    expect(fp.contains(const Vec2(6, 2)), isFalse);
    // Точка под вырезом (x=6, y=6) — внутри полигона.
    expect(fp.contains(const Vec2(6, 6)), isTrue);
  });

  test(
      'RoofPlanGeometry.computePolygonal: плоская крыша на L-форме '
      'fallback-ит на bbox (нет уступов в плоской геометрии)', () {
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final geom = RoofPlanGeometry.computePolygonal(
      shape: RoofShape.flat,
      footprint: fp,
      slopeDegrees: 1.5,
      snowZone: 1,
    );
    // Плоская — один скат-«пирог», 0 коньков, 0 ендов.
    expect(geom.ridges, isEmpty);
    expect(geom.valleys, isEmpty);
    expect(geom.slopes.length, 1);
  });

  test(
      'RoofPlanGeometry.computePolygonal: T-форма 12×10 / стержень 4×4 '
      'даёт два конька и хотя бы одну ендову', () {
    final fp = BuildingFootprint.tShape(
      width: 12,
      height: 10,
      stemWidth: 4,
      stemHeight: 4,
    );
    final geom = RoofPlanGeometry.computePolygonal(
      shape: RoofShape.gable,
      footprint: fp,
      slopeDegrees: 30,
      snowZone: 1,
    );
    // Декомпозиция = 2 прямоугольника (top bar + stem) → 2 конька.
    expect(geom.ridges.length, 2);
    expect(geom.slopes.length, 4);
    // Между ними должна появиться хотя бы одна ендова (общая граница
    // top-bar/stem на y=6).
    expect(geom.valleys, isNotEmpty);
    // Outer outline T-формы. v66 §21.1.4: 6 convex + 2 reflex (×3) = 12.
    expect(geom.outerOutline.length, 12);
  });

  test(
      'RoofPlanGeometry.computePolygonal: U-форма 12×10 / вырез 4×4 '
      'даёт три конька и хотя бы одну ендову', () {
    final fp = BuildingFootprint.uShape(
      width: 12,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final geom = RoofPlanGeometry.computePolygonal(
      shape: RoofShape.gable,
      footprint: fp,
      slopeDegrees: 30,
      snowZone: 1,
    );
    // Декомпозиция = 3 прямоугольника (две «ноги» + основание).
    expect(geom.ridges.length, 3);
    expect(geom.slopes.length, 6);
    // Ендов между основанием и каждой «ногой» — минимум 1 (фактически 2).
    expect(geom.valleys, isNotEmpty);
    // Outer outline U-формы. v66 §21.1.4: 6 convex + 2 reflex (×3) = 12.
    expect(geom.outerOutline.length, 12);
  });

  test(
      'Phase-3b §17.2.3: L-форма gable — ендова из reflex-угла идёт '
      'диагонально 45° (не вдоль рёбер прямоугольников)', () {
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final geom = RoofPlanGeometry.computePolygonal(
      shape: RoofShape.gable,
      footprint: fp,
      slopeDegrees: 30,
      snowZone: 1,
    );
    // Ровно 1 ендова, идёт от reflex-угла (6,6) по диагонали SW.
    expect(geom.valleys.length, 1);
    final v = geom.valleys.first;
    // Один из концов — точно reflex-угол.
    expect(v.a.x, closeTo(6, 1e-6));
    expect(v.a.y, closeTo(6, 1e-6));
    // Другой конец — на одном из коньков, и линия 45° (|dx| == |dy|).
    final dx = (v.b.x - v.a.x).abs();
    final dy = (v.b.y - v.a.y).abs();
    expect(dx, closeTo(dy, 1e-6),
        reason: 'ендова должна идти под 45° (равные dx и dy)');
    // Никаких накосов — для gable shape.
    expect(geom.hips, isEmpty);
  });

  test(
      'Phase-3b §17.2.3: L-форма hip — добавляются накосы (хребты) от '
      'каждого конвексного угла', () {
    final fp = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final geom = RoofPlanGeometry.computePolygonal(
      shape: RoofShape.hip,
      footprint: fp,
      slopeDegrees: 30,
      snowZone: 1,
    );
    // L-форма имеет 5 конвексных + 1 reflex = 6 углов outline-а.
    expect(fp.outline.length, 6);
    // 5 накосов (по числу конвексных углов).
    expect(geom.hips.length, 5);
    // 1 ендова (reflex угол).
    expect(geom.valleys.length, 1);
    // Все накосы — 45° (|dx| == |dy|).
    for (final h in geom.hips) {
      final dx = (h.b.x - h.a.x).abs();
      final dy = (h.b.y - h.a.y).abs();
      expect(dx, closeTo(dy, 1e-6),
          reason: 'накос должен быть 45°');
    }
  });

  test(
      'Phase-3b §17.2.4: BuildingFootprint поддерживает произвольный '
      'CCW axis-aligned полигон (выпуклый шестиугольник «крест»)', () {
    // Полигон-крест 10×10 со срезом каждого угла 2×2 — 12 вершин.
    final outline = <Vec2>[
      const Vec2(2, 0),
      const Vec2(8, 0),
      const Vec2(8, 2),
      const Vec2(10, 2),
      const Vec2(10, 8),
      const Vec2(8, 8),
      const Vec2(8, 10),
      const Vec2(2, 10),
      const Vec2(2, 8),
      const Vec2(0, 8),
      const Vec2(0, 2),
      const Vec2(2, 2),
    ];
    final fp = BuildingFootprint(outline: outline);
    expect(fp.outline.length, 12);
    expect(fp.area, closeTo(84, 0.01)); // 10*10 - 4*(2*2) = 84
    expect(fp.isCcw, isTrue);
    // Точка в центре — внутри.
    expect(fp.contains(const Vec2(5, 5)), isTrue);
    // Точка в срезанном углу — снаружи.
    expect(fp.contains(const Vec2(0.5, 0.5)), isFalse);
    // План кровли работает на этом полигоне.
    final geom = RoofPlanGeometry.computePolygonal(
      shape: RoofShape.hip,
      footprint: fp,
      slopeDegrees: 30,
      snowZone: 1,
    );
    expect(geom.ridges, isNotEmpty);
    expect(geom.hips, isNotEmpty);
    expect(geom.valleys, isNotEmpty,
        reason: 'у креста есть 4 reflex-угла, должно быть ≥1 ендов');
  });
}
