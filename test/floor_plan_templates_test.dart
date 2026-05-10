// Phase-3b §17.2.2: тесты каталога из 12 шаблонов планировок.

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/floor_plan_templates.dart';
import 'package:construction_calculator/data/rooms_catalog.dart';
import 'package:construction_calculator/models/client_brief.dart';

void main() {
  test('FloorPlanTemplateLibrary.all содержит ровно 12 архетипов', () {
    expect(FloorPlanTemplateLibrary.all.length, 12,
        reason: 'каталог фиксирован: ровно 12 шаблонов по §17.2.2');
  });

  test('Все идентификаторы шаблонов уникальны', () {
    final ids = FloorPlanTemplateLibrary.all.map((t) => t.id).toSet();
    expect(ids.length, 12,
        reason: 'каждый шаблон должен иметь уникальный stable id');
  });

  test('Все шаблоны имеют валидные обязательные поля', () {
    for (final t in FloorPlanTemplateLibrary.all) {
      expect(t.title, isNotEmpty, reason: '${t.id}: пустой title');
      expect(t.tagline, isNotEmpty, reason: '${t.id}: пустой tagline');
      expect(t.description, isNotEmpty, reason: '${t.id}: пустой description');
      expect(t.footprintWidth, greaterThan(0));
      expect(t.footprintLength, greaterThan(0));
      expect(t.floors, inInclusiveRange(1, 3));
      expect(t.rooms, isNotEmpty, reason: '${t.id}: rooms не должен быть пуст');
      // Обязательно содержит как минимум одну спальню или гостиную.
      final hasLivingSpace = t.rooms.containsKey(RoomKind.bedroom) ||
          t.rooms.containsKey(RoomKind.kidsRoom) ||
          t.rooms.containsKey(RoomKind.livingRoom);
      expect(hasLivingSpace, isTrue,
          reason: '${t.id}: должна быть жилая комната');
    }
  });

  test('FloorPlanTemplate.applyTo переносит габариты, этажность и состав',
      () {
    final brief = ClientBrief();
    final t = FloorPlanTemplateLibrary.findById('typical-8x10')!;
    t.applyTo(brief);
    expect(brief.floors, 2.toString().contains('') ? t.floors : t.floors);
    expect(brief.floors, t.floors);
    expect(brief.footprintWidth, 8);
    expect(brief.footprintLength, 10);
    expect(brief.targetArea, 80);
    expect(brief.rooms[RoomKind.bedroom.name], 2);
    expect(brief.hasMansard, false);
    expect(brief.hasGarage, false);
  });

  test(
      'FloorPlanTemplate.applyTo заменяет состав комнат, не докидывает '
      'старые', () {
    final brief = ClientBrief()
      ..rooms[RoomKind.kidsRoom.name] = 5
      ..rooms[RoomKind.bedroom.name] = 99;
    final t = FloorPlanTemplateLibrary.findById('econom-6x8')!;
    t.applyTo(brief);
    // Старая «детская:5» должна быть очищена.
    expect(brief.rooms.containsKey(RoomKind.kidsRoom.name), isFalse);
    // Спальня должна быть равна значению из шаблона, не 99.
    expect(brief.rooms[RoomKind.bedroom.name], 1);
  });

  test('L-форма шаблоны имеют непустой footprint', () {
    final l1 = FloorPlanTemplateLibrary.findById('l-shape-1-storey-10x10')!;
    final l2 = FloorPlanTemplateLibrary.findById('l-shape-2-storey-12x10')!;
    expect(l1.footprint, isNotNull);
    expect(l2.footprint, isNotNull);
    expect(l1.footprint!.outline.length, 6,
        reason: 'L-форма имеет 6 вершин');
    // Площадь полигона (84 м² для 10×10/4×4) должна быть меньше bbox.
    expect(l1.footprint!.area,
        closeTo(84, 0.01),
        reason: 'L 10×10/4×4 = 84 м²');
    // L 12×10/5×4 = 100 м².
    expect(l2.footprint!.area,
        closeTo(100, 0.01),
        reason: 'L 12×10/5×4 = 100 м²');
  });

  test('Прямоугольные шаблоны имеют footprint == null', () {
    final t = FloorPlanTemplateLibrary.findById('typical-8x10')!;
    expect(t.footprint, isNull);
  });

  test('FloorPlanTemplateLibrary.findById возвращает null для unknown id', () {
    expect(FloorPlanTemplateLibrary.findById('nonexistent-id'), isNull);
  });
}
