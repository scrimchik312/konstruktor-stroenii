// Каноническая палитра помещений для рендера планов АР.
//
// Соответствует §5.2 техзадания konstruktor_stroenii_full_spec.md.
// Цвета подобраны так, чтобы: (а) визуально совпадать с референсами
// каталожных проектов (ccnova-style, GoldenLog, T-237 и т.п.); (б) при
// печати в ч/б оставалась читаемость подписей и оси.
//
// Используется только для заливки внутреннего прямоугольника комнаты
// поверх «массы стены» — поверх палитры рисуется штриховка пола (только
// в ванных), мебель, подписи, оси.

import 'package:pdf/pdf.dart';

import '../data/rooms_catalog.dart';
import '../models/floor_plan.dart';

/// Возвращает PDF-цвет заливки комнаты по `roomKindName`.
/// Если `roomKindName` не задан или не распознан, используется
/// fallback по `PlanRoomKind` (старое поведение).
class RoomPalette {
  // Палитра помещений — из спецификации (RGB-Hex).
  // Тёплые цвета — спальная зона, холодные — санузлы и техпомещения,
  // нейтральные — общественные/проходные.
  static const PdfColor _bedroom = PdfColor.fromInt(0xFFFCE4EC); // светло-розовый
  static const PdfColor _kidsRoom = PdfColor.fromInt(0xFFFFF3CD); // ванильный
  static const PdfColor _livingRoom = PdfColor.fromInt(0xFFFFEFD8); // персиковый
  static const PdfColor _kitchen = PdfColor.fromInt(0xFFE8F5E9); // светло-зелёный
  static const PdfColor _kitchenDining = PdfColor.fromInt(0xFFE0F2E1);
  static const PdfColor _dining = PdfColor.fromInt(0xFFFFF8E1); // тёплый бежевый
  static const PdfColor _bathroom = PdfColor.fromInt(0xFFEDE7F6); // лавандовый
  static const PdfColor _toilet = PdfColor.fromInt(0xFFE3F2FD); // голубой
  static const PdfColor _laundry = PdfColor.fromInt(0xFFE1F5FE);
  static const PdfColor _hallway = PdfColor.fromInt(0xFFF5F5F5); // нейтрально-серый
  static const PdfColor _study = PdfColor.fromInt(0xFFE8EAF6); // голубой холодный
  static const PdfColor _wardrobe = PdfColor.fromInt(0xFFFFF1E6); // тёплый песочный
  static const PdfColor _boilerRoom = PdfColor.fromInt(0xFFECEFF1); // тёплый серый
  static const PdfColor _storage = PdfColor.fromInt(0xFFEFEBE9); // песочный
  static const PdfColor _staircase = PdfColor.fromInt(0xFFF6F2FA); // совпадает с _staircaseFill в pdf_builder
  static const PdfColor _garage = PdfColor.fromInt(0xFFEEEEEE); // нейтральный «бетон»
  static const PdfColor _terrace = PdfColor.fromInt(0xFFF1F8E9); // лёгкий «мятный»
  static const PdfColor _balcony = PdfColor.fromInt(0xFFF1F8E9);
  static const PdfColor _pantry = PdfColor.fromInt(0xFFEFEBE9);
  static const PdfColor _technical = PdfColor.fromInt(0xFFECEFF1);

  /// Цвет «свободной» (необъявленной) зоны — нейтральный светлый,
  /// совпадает с `_freeFill` в pdf_builder.
  static const PdfColor _freeFallback = PdfColor.fromInt(0xFFFAFAFA);

  /// Цвет обычной комнаты без заданного типа — белый, как было до Phase-1.
  static const PdfColor _roomFallback = PdfColors.white;

  /// Подобрать цвет заливки для комнаты на плане.
  static PdfColor fillFor(PlanRoom room) {
    final byName = _byName(room.roomKindName);
    if (byName != null) return byName;
    switch (room.kind) {
      case PlanRoomKind.staircase:
        return _staircase;
      case PlanRoomKind.free:
        return _freeFallback;
      case PlanRoomKind.room:
        return _roomFallback;
    }
  }

  /// Прямой маппинг RoomKind → цвет (без fallback'а на PlanRoomKind).
  /// Возвращает `null` для неизвестных значений.
  static PdfColor? _byName(String? name) {
    if (name == null || name.isEmpty) return null;
    final kind = RoomKind.values
        .where((k) => k.name == name)
        .cast<RoomKind?>()
        .firstWhere((_) => true, orElse: () => null);
    if (kind == null) return null;
    return fillForKind(kind);
  }

  /// Прямой маппинг RoomKind → цвет.
  static PdfColor fillForKind(RoomKind kind) {
    switch (kind) {
      case RoomKind.bedroom:
        return _bedroom;
      case RoomKind.bathroom:
        return _bathroom;
      case RoomKind.kitchen:
        return _kitchen;
      case RoomKind.livingRoom:
        return _livingRoom;
      case RoomKind.study:
        return _study;
      case RoomKind.hallway:
        return _hallway;
      case RoomKind.boilerRoom:
        return _boilerRoom;
      case RoomKind.storage:
        return _storage;
      case RoomKind.wardrobe:
        return _wardrobe;
      case RoomKind.kidsRoom:
        return _kidsRoom;
      case RoomKind.dining:
        return _dining;
      case RoomKind.kitchenDining:
        return _kitchenDining;
      case RoomKind.toilet:
        return _toilet;
      case RoomKind.laundry:
        return _laundry;
      case RoomKind.garage:
        return _garage;
      case RoomKind.terrace:
        return _terrace;
      case RoomKind.balcony:
        return _balcony;
      case RoomKind.pantry:
        return _pantry;
      case RoomKind.technical:
        return _technical;
    }
  }
}
