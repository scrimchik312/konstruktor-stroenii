/// Тип грунта на участке.
///
/// Список соответствует общей классификации в инженерно-геологических
/// изысканиях, упрощён до уровня «бытового» опросника.
enum SoilType {
  sand,
  sandyLoam,
  loam,
  clay,
  peat,
  rock;

  String get title {
    switch (this) {
      case SoilType.sand:
        return 'Песок';
      case SoilType.sandyLoam:
        return 'Супесь';
      case SoilType.loam:
        return 'Суглинок';
      case SoilType.clay:
        return 'Глина';
      case SoilType.peat:
        return 'Торф';
      case SoilType.rock:
        return 'Скальный грунт';
    }
  }

  static SoilType? fromName(String? name) {
    if (name == null) return null;
    for (final v in SoilType.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
