/// Фиксированный каталог помещений, по которому собирается состав комнат.
///
/// Ключ совпадает с [RoomKind.name], значение — заголовок для UI.
/// Полный набор не меняется в зависимости от проекта: пользователь только
/// задаёт количество каждого типа помещений (счётчиками +/−).
enum RoomKind {
  bedroom,
  bathroom,
  kitchen,
  livingRoom,
  study,
  hallway,
  boilerRoom,
  storage,
  wardrobe,
  // Расширенный набор типов помещений из ТЗ (Phase-1 MVP).
  // Эти типы пока не выводятся в UI бриф-визарда (см. `userSelectable`),
  // но используются палитрой и расстановщиком мебели на сгенерированных
  // планах.
  kidsRoom,
  dining,
  kitchenDining,
  toilet,
  laundry,
  garage,
  terrace,
  balcony,
  pantry,
  technical;

  String get title {
    switch (this) {
      case RoomKind.bedroom:
        return 'Спальня';
      case RoomKind.bathroom:
        return 'Санузел';
      case RoomKind.kitchen:
        return 'Кухня';
      case RoomKind.livingRoom:
        return 'Гостиная';
      case RoomKind.study:
        return 'Кабинет';
      case RoomKind.hallway:
        return 'Прихожая';
      case RoomKind.boilerRoom:
        return 'Котельная';
      case RoomKind.storage:
        return 'Кладовая';
      case RoomKind.wardrobe:
        return 'Гардеробная';
      case RoomKind.kidsRoom:
        return 'Детская';
      case RoomKind.dining:
        return 'Столовая';
      case RoomKind.kitchenDining:
        return 'Кухня-столовая';
      case RoomKind.toilet:
        return 'Туалет';
      case RoomKind.laundry:
        return 'Постирочная';
      case RoomKind.garage:
        return 'Гараж';
      case RoomKind.terrace:
        return 'Терраса';
      case RoomKind.balcony:
        return 'Балкон';
      case RoomKind.pantry:
        return 'Кладовая';
      case RoomKind.technical:
        return 'Техпомещение';
    }
  }

  /// Показывать ли этот тип помещения в бриф-визарде. Только основные
  /// функциональные помещения; технические/деривативные значения
  /// (terrace/balcony/garage и т.п.) не предлагаются пользователю и
  /// выводятся автоматически по соответствующим флагам брифа.
  bool get userSelectable {
    switch (this) {
      case RoomKind.bedroom:
      case RoomKind.bathroom:
      case RoomKind.kitchen:
      case RoomKind.livingRoom:
      case RoomKind.study:
      case RoomKind.hallway:
      case RoomKind.boilerRoom:
      case RoomKind.storage:
      case RoomKind.wardrobe:
        return true;
      // Phase-1 расширения остаются скрытыми в UI до фазы 2 — это
      // даёт возможность подключить рендер мебели/палитры без
      // изменения существующего бриф-визарда и набора генерируемых
      // комнат.
      case RoomKind.kidsRoom:
      case RoomKind.dining:
      case RoomKind.kitchenDining:
      case RoomKind.toilet:
      case RoomKind.laundry:
      case RoomKind.garage:
      case RoomKind.terrace:
      case RoomKind.balcony:
      case RoomKind.pantry:
      case RoomKind.technical:
        return false;
    }
  }

  /// Подсказка по умолчанию (сколько таких помещений обычно бывает).
  int get defaultCount {
    switch (this) {
      case RoomKind.bedroom:
        return 2;
      case RoomKind.bathroom:
        return 1;
      case RoomKind.kitchen:
        return 1;
      case RoomKind.livingRoom:
        return 1;
      case RoomKind.study:
        return 0;
      case RoomKind.hallway:
        return 1;
      case RoomKind.boilerRoom:
        return 1;
      case RoomKind.storage:
        return 0;
      case RoomKind.wardrobe:
        return 0;
      case RoomKind.kidsRoom:
      case RoomKind.dining:
      case RoomKind.kitchenDining:
      case RoomKind.toilet:
      case RoomKind.laundry:
      case RoomKind.garage:
      case RoomKind.terrace:
      case RoomKind.balcony:
      case RoomKind.pantry:
      case RoomKind.technical:
        return 0;
    }
  }
}
