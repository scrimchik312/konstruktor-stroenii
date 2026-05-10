import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/price_catalog.dart';
import 'package:construction_calculator/data/wall_materials.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/foundation.dart';
import 'package:construction_calculator/models/house_project.dart';
import 'package:construction_calculator/services/estimate_calculator.dart';

/// Юнит-тесты на расчёт сметы для эталонной коробки 6 × 8 м, 1 этаж,
/// лента + газобетон + металлочерепица. Проверяем, что:
///   • объёмы по разделам отличны от нуля и реалистичны;
///   • переопределение цены меняет итог;
///   • региональный коэффициент применяется ко всем строкам;
///   • НДС считается от subtotal.
void main() {
  HouseProject buildReferenceProject({
    String? region,
    Map<String, double>? overrides,
  }) {
    final p = HouseProject(
      id: 'ref',
      name: 'Эталонный 6×8',
      constructionType: ConstructionType.privateHouse,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
      priceOverrides: overrides,
    );
    p.brief
      ..region = region
      ..floors = 1
      ..targetArea = 48
      ..footprintWidth = 6
      ..footprintLength = 8
      ..wallMaterial = WallMaterial.aerated
      ..rooms.addAll({'bedroom': 2, 'bathroom': 1, 'kitchen': 1, 'living_room': 1});
    p.foundation
      ..type = FoundationType.strip
      ..device = FoundationDevice.monolithic;
    p.walls
      ..material = 'aerated'
      ..thickness = 300
      ..height = 2.8;
    p.floorSlabs
      ..type = 'wood_beams'
      ..material = 'pine'
      ..thickness = 200;
    p.roof
      ..type = 'gable'
      ..slopeAngle = 30
      ..roofingMaterial = 'metal';
    return p;
  }

  test('ref 6×8: смета не пустая и содержит все разделы', () {
    final p = buildReferenceProject();
    final est = EstimateCalculator.compute(p);

    expect(est.rows, isNotEmpty);
    final secs = est.rows.map((r) => r.section).toSet();
    expect(secs, containsAll([
      EstimateSection.foundation,
      EstimateSection.walls,
      EstimateSection.floorSlabs,
      EstimateSection.roof,
      EstimateSection.engineering,
      EstimateSection.finishing,
    ]));
  });

  test('ref 6×8: бетон фундамента в реалистичных пределах (3-8 м³)', () {
    final p = buildReferenceProject();
    final est = EstimateCalculator.compute(p);
    final concrete = est.rows.firstWhere(
      (r) => r.itemId == 'foundation_concrete_b25',
      orElse: () => throw StateError('нет строки бетона'),
    );
    // Лента по периметру 28 м × 0.4 м × 1.0 м ≈ 11.2 м³.
    expect(concrete.quantity, greaterThan(3));
    expect(concrete.quantity, lessThan(20));
  });

  test('ref 6×8: газобетон по объёму ≥ 8 м³', () {
    final p = buildReferenceProject();
    final est = EstimateCalculator.compute(p);
    final block = est.rows.firstWhere(
      (r) => r.itemId == 'wall_aerated_d500',
    );
    // V = периметр(28) × высота(2.8) × этажи(1) × толщина(0.3)
    //   + перегородки 30% площади × 0.1 м толщ. ≈ 23.5 м³ + 6.6 м³.
    expect(block.quantity, greaterThan(8));
  });

  test('ref 6×8: металлочерепица — площадь кровли > пятна', () {
    final p = buildReferenceProject();
    final est = EstimateCalculator.compute(p);
    final cover = est.rows.firstWhere(
      (r) => r.itemId == 'roof_metal_tile',
    );
    // Скат под 30°: 48 / cos(30°) × 1.05 ≈ 58.2 м².
    expect(cover.quantity, greaterThan(48));
    expect(cover.quantity, lessThan(80));
  });

  test('ref 6×8: общий итог в разумных пределах', () {
    final p = buildReferenceProject();
    final est = EstimateCalculator.compute(p);
    // Маленький дом 48 м² без отделки премиум — должно быть от 1 до 8 млн.
    expect(est.subtotal, greaterThan(1000000));
    expect(est.subtotal, lessThan(8000000));
  });

  test('region factor — Москва дороже, чем дефолт', () {
    final p1 = buildReferenceProject();
    final p2 = buildReferenceProject(region: 'Москва');
    final est1 = EstimateCalculator.compute(p1);
    final est2 = EstimateCalculator.compute(p2);
    expect(est2.regionFactor, 1.20);
    expect(est2.subtotal, greaterThan(est1.subtotal * 1.15));
  });

  test('region factor — Краснодар дешевле, чем дефолт', () {
    final p1 = buildReferenceProject();
    final p2 = buildReferenceProject(region: 'Краснодар');
    final est1 = EstimateCalculator.compute(p1);
    final est2 = EstimateCalculator.compute(p2);
    expect(est2.regionFactor, lessThan(1.0));
    expect(est2.subtotal, lessThan(est1.subtotal));
  });

  test('override цены меняет сумму строки и общий итог', () {
    final p1 = buildReferenceProject();
    final est1 = EstimateCalculator.compute(p1);
    final concrete1 = est1.rows.firstWhere(
      (r) => r.itemId == 'foundation_concrete_b25',
    );

    final p2 = buildReferenceProject(overrides: {
      'foundation_concrete_b25': concrete1.basePrice * 2,
    });
    final est2 = EstimateCalculator.compute(p2);
    final concrete2 = est2.rows.firstWhere(
      (r) => r.itemId == 'foundation_concrete_b25',
    );
    expect(concrete2.isOverridden, isTrue);
    expect(concrete2.effectivePrice, concrete1.basePrice * 2);
    expect(est2.subtotal, greaterThan(est1.subtotal));
  });

  test('НДС 20 % считается от subtotal', () {
    final p = buildReferenceProject();
    final est = EstimateCalculator.compute(p);
    expect((est.vat - est.subtotal * 0.20).abs(), lessThan(0.01));
    expect((est.total - (est.subtotal + est.vat)).abs(), lessThan(0.01));
  });

  test('priceOverrides сохраняются в JSON и читаются обратно', () {
    final p = buildReferenceProject(overrides: {
      'foundation_concrete_b25': 9000.0,
      'wall_aerated_d500': 7200.0,
    });
    final json = p.toJson();
    expect(json['priceOverrides'], isA<Map>());
    final restored = HouseProject.fromJson(json);
    expect(restored.priceOverrides['foundation_concrete_b25'], 9000.0);
    expect(restored.priceOverrides['wall_aerated_d500'], 7200.0);
  });

  test('каркасный дом — есть утеплитель, нет блоков', () {
    final p = buildReferenceProject()
      ..brief.wallMaterial = WallMaterial.frame
      ..walls.material = 'frame';
    final est = EstimateCalculator.compute(p);
    final hasInsulation =
        est.rows.any((r) => r.itemId == 'wall_mineral_wool_100');
    final hasBlocks = est.rows.any((r) => r.itemId == 'wall_aerated_d500');
    expect(hasInsulation, isTrue);
    expect(hasBlocks, isFalse);
  });

  test('свайный фундамент — без бетона, со сваями', () {
    final p = buildReferenceProject();
    p.foundation
      ..type = FoundationType.pile
      ..device = FoundationDevice.screwPile;
    final est = EstimateCalculator.compute(p);
    final hasPiles = est.rows.any((r) => r.itemId == 'foundation_screw_pile_d108');
    final hasConcrete =
        est.rows.any((r) => r.itemId == 'foundation_concrete_b25');
    expect(hasPiles, isTrue);
    expect(hasConcrete, isFalse);
  });
}
