import '../data/region_catalog.dart';
import '../data/rooms_catalog.dart';
import '../data/soil_types.dart';
import '../data/wall_materials.dart';
import 'borehole.dart';
import 'layout_scheme.dart';
import 'soil_layer.dart';

/// Техническое задание клиента — пожелания, которые мы собираем перед расчётами.
///
/// Заполняется через многошаговый визард и автосохраняется после каждого
/// шага. На основе технического задания движок правил подбирает состав сооружения.
class ClientBrief {
  /// Город из каталога [kRegionCatalog] либо введённый вручную (в режиме
  /// проектировщика).
  String? region;

  /// Снеговой район (1..8), по СП 20.13330.2016.
  int? snowZone;

  /// Ветровой район (Ia..VII).
  String? windZone;

  /// Геологические скважины на участке (инженерно-геологические
  /// изыскания). По СП 47.13330.2016 для ИЖС — не менее 2-3 скважин
  /// глубиной 5-7 м.
  ///
  /// Каждая скважина хранит свои слои грунта и уровень подземных
  /// вод (УГВ) на момент бурения. Первая скважина (индекс 0)
  /// считается «расчётной» — именно её данные используются
  /// во всех расчётах (фундамент, теплотехника и т. п.).
  /// Остальные скважины попадают в ведомость изысканий
  /// и на ситуационный план.
  final List<Borehole> boreholes;

  /// Слои расчётной (первой) скважины — бэкворд-совместимый
  /// интерфейс для остального кода. Все изменения (add/remove)
  /// применяются к [boreholes].first.layers.
  List<SoilLayer> get soilLayers {
    _ensureAtLeastOneBorehole();
    return boreholes.first.layers;
  }

  /// УГВ расчётной (первой) скважины. Используется при расчёте
  /// фундамента (СП 22.13330.2016 п. 5.5.5):
  ///  • если УГВ выше глубины заложения — нужна гидроизоляция и/или
  ///    замена грунта;
  ///  • если УГВ ≥ глубины промерзания — пучинистость грунта снижена.
  double? get groundwaterLevelM {
    _ensureAtLeastOneBorehole();
    return boreholes.first.groundwaterLevelM;
  }

  set groundwaterLevelM(double? v) {
    _ensureAtLeastOneBorehole();
    boreholes.first.groundwaterLevelM = v;
  }

  void _ensureAtLeastOneBorehole() {
    if (boreholes.isEmpty) boreholes.add(Borehole(label: 'С-1'));
  }

  /// Тип грунта верхнего/первого слоя в расчётной скважине —
  /// удобный геттер для случаев, когда нужно одно «обобщённое» значение.
  SoilType? get soilType =>
      soilLayers.isEmpty ? null : soilLayers.first.type;

  /// Этажность (1, 2, 3).
  int? floors;

  /// Признаки наличия: мансарда, подвал, гараж, терраса, балкон, эркер,
  /// второй свет, лестница (явный запрос).
  bool? hasMansard;
  bool? hasBasement;
  bool? hasGarage;
  bool? hasTerrace;
  bool? hasBalcony;
  bool? hasOriel; // эркер
  bool? hasDoubleHeight; // второй свет
  bool? hasStaircase;

  /// Целевая общая площадь, м².
  double? targetArea;

  /// Габариты пятна застройки, м.
  double? footprintWidth;
  double? footprintLength;

  /// Состав комнат: ключ — [RoomKind.name], значение — количество.
  ///
  /// Это «общее» техническое задание по составу — генератор сам
  /// распределяет комнаты по этажам (см. [FloorPlanGenerator]).
  final Map<String, int> rooms;

  /// Per-floor состав комнат: ключ — этаж в формате `'1'`, `'2'`, ... или
  /// `'mansard'`; значение — `Map<RoomKind.name, int>`. Если карта пустая
  /// — генератор использует автоматический алгоритм распределения.
  /// Если карта непустая — она имеет приоритет: каждый этаж берёт ровно
  /// перечисленные в нём комнаты.
  ///
  /// Активируется чекбоксом «Распределить вручную по этажам» в визарде.
  final Map<String, Map<String, int>> floorRooms;

  /// Желаемый материал стен.
  WallMaterial? wallMaterial;

  /// Схема планировки этажа (коридорная по умолчанию).
  ///
  /// Используется как «базовая» схема, когда в [floorSchemes] нет
  /// явного значения для этажа.
  LayoutScheme layoutScheme = LayoutScheme.corridor;

  /// Per-floor схемы планировки: ключ — этаж в формате [ClientBrief.floorKey]
  /// (`'1'`, `'2'`, `'mansard'`); значение — [LayoutScheme.name].
  ///
  /// Если карта пустая или для конкретного этажа нет записи —
  /// [FloorPlanGenerator] использует «базовую» [layoutScheme]. Это
  /// позволяет выбирать разные схемы для каждого этажа отдельно
  /// (например, 1 этаж — зальная, 2 этаж — коридорная).
  final Map<String, String> floorSchemes;

  /// Спецификация гаража (Ш×Д×В + тип кровли + материал стен).
  /// Используется только если [hasGarage] == true. Если null —
  /// пользователь ещё не задал габариты (визард просит ввести
  /// после выбора чекбокса «Гараж»).
  AttachmentSpec? garageSpec;

  /// Спецификация террасы (Ш×Д×В + тип кровли + крытая/открытая).
  /// Используется только если [hasTerrace] == true.
  AttachmentSpec? terraceSpec;

  /// Семя (RNG seed) для параметризованной генерации планов.
  /// Меняется при нажатии «Сгенерировать другой вариант» (п.9 v40).
  /// null = детерминированная генерация (как было исторически).
  int? planSeed;

  /// Семя для генерации габаритов дома (п.8 v40). Меняется при
  /// повторном нажатии кнопки «Авто-габариты».
  int? footprintSeed;

  /// Особые пожелания клиента в свободной форме.
  String? specialRequirements;

  ClientBrief({
    this.region,
    this.snowZone,
    this.windZone,
    List<SoilLayer>? soilLayers,
    double? groundwaterLevelM,
    List<Borehole>? boreholes,
    this.floors,
    this.hasMansard,
    this.hasBasement,
    this.hasGarage,
    this.hasTerrace,
    this.hasBalcony,
    this.hasOriel,
    this.hasDoubleHeight,
    this.hasStaircase,
    this.targetArea,
    this.footprintWidth,
    this.footprintLength,
    Map<String, int>? rooms,
    Map<String, Map<String, int>>? floorRooms,
    this.wallMaterial,
    LayoutScheme? layoutScheme,
    Map<String, String>? floorSchemes,
    this.garageSpec,
    this.terraceSpec,
    this.planSeed,
    this.footprintSeed,
    this.specialRequirements,
  })  : layoutScheme = layoutScheme ?? LayoutScheme.corridor,
        rooms = rooms ?? <String, int>{},
        floorRooms = floorRooms ?? <String, Map<String, int>>{},
        floorSchemes = floorSchemes ?? <String, String>{},
        boreholes = boreholes ?? <Borehole>[] {
    // Гарантируем наличие как минимум одной (расчётной) скважины
    // и при необходимости переносим в неё старые «одиночные»
    // soilLayers / groundwaterLevelM (миграция с формата v3.5).
    if (this.boreholes.isEmpty) {
      this.boreholes.add(Borehole(label: 'С-1'));
    }
    if ((soilLayers != null && soilLayers.isNotEmpty) &&
        this.boreholes.first.layers.isEmpty) {
      this.boreholes.first.layers.addAll(soilLayers);
    }
    if (groundwaterLevelM != null &&
        this.boreholes.first.groundwaterLevelM == null) {
      this.boreholes.first.groundwaterLevelM = groundwaterLevelM;
    }
  }

  bool get isStarted =>
      region != null ||
      soilLayers.any((l) => !l.isEmpty) ||
      floors != null ||
      targetArea != null ||
      rooms.values.any((v) => v > 0) ||
      wallMaterial != null ||
      (specialRequirements?.isNotEmpty ?? false);

  /// Все ключевые поля заполнены (готовый техническое задание).
  bool get isComplete =>
      region != null &&
      snowZone != null &&
      windZone != null &&
      soilLayers.any((l) => l.type != null) &&
      floors != null &&
      targetArea != null &&
      footprintWidth != null &&
      footprintLength != null &&
      wallMaterial != null;

  /// Нужна ли лестница: либо явный флаг, либо этажность > 1, либо мансарда,
  /// либо подвал.
  bool get requiresStaircase {
    if (hasStaircase == true) return true;
    if ((floors ?? 1) > 1) return true;
    if (hasMansard == true) return true;
    if (hasBasement == true) return true;
    return false;
  }

  String get summary {
    if (!isStarted) return 'Не заполнен';
    final parts = <String>[];
    if (floors != null) {
      parts.add('${floors!} эт.${hasMansard == true ? ' + мансарда' : ''}');
    }
    if (targetArea != null) {
      parts.add('${targetArea!.toStringAsFixed(0)} м²');
    }
    if (region != null) parts.add(region!);
    if (parts.isEmpty) return 'Заполняется';
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'region': region,
        'snowZone': snowZone,
        'windZone': windZone,
        'soilLayers': soilLayers.map((l) => l.toJson()).toList(),
        'groundwaterLevelM': groundwaterLevelM,
        'boreholes': boreholes.map((b) => b.toJson()).toList(),
        'floors': floors,
        'hasMansard': hasMansard,
        'hasBasement': hasBasement,
        'hasGarage': hasGarage,
        'hasTerrace': hasTerrace,
        'hasBalcony': hasBalcony,
        'hasOriel': hasOriel,
        'hasDoubleHeight': hasDoubleHeight,
        'hasStaircase': hasStaircase,
        'targetArea': targetArea,
        'footprintWidth': footprintWidth,
        'footprintLength': footprintLength,
        'rooms': rooms,
        'floorRooms': floorRooms,
        'wallMaterial': wallMaterial?.name,
        'layoutScheme': layoutScheme.name,
        'floorSchemes': floorSchemes,
        'garageSpec': garageSpec?.toJson(),
        'terraceSpec': terraceSpec?.toJson(),
        'planSeed': planSeed,
        'footprintSeed': footprintSeed,
        'specialRequirements': specialRequirements,
      };

  /// Ключ этажа в [floorRooms] / [floorSchemes] для индекса
  /// [floorIndex] / признака мансарды. Этажи нумеруются от 1;
  /// мансарда — отдельный ключ `'mansard'`.
  static String floorKey(int floorIndex, {bool mansard = false}) =>
      mansard ? 'mansard' : '$floorIndex';

  /// Схема планировки для конкретного этажа. Если в [floorSchemes]
  /// есть запись для [key] — возвращаем её; иначе — базовую
  /// [layoutScheme]. Неизвестные имена фолбэчат на [layoutScheme].
  LayoutScheme schemeForFloor(String key) {
    final raw = floorSchemes[key];
    if (raw == null || raw.isEmpty) return layoutScheme;
    final s = LayoutScheme.fromName(raw);
    return s;
  }

  static ClientBrief fromJson(Map<String, dynamic> json) {
    final rawRooms = json['rooms'];
    final rooms = <String, int>{};
    if (rawRooms is Map) {
      rawRooms.forEach((k, v) {
        if (v is int) rooms[k.toString()] = v;
      });
    }
    final rawFloorRooms = json['floorRooms'];
    final floorRooms = <String, Map<String, int>>{};
    if (rawFloorRooms is Map) {
      rawFloorRooms.forEach((k, v) {
        if (v is Map) {
          final inner = <String, int>{};
          v.forEach((ik, iv) {
            if (iv is int) inner[ik.toString()] = iv;
          });
          if (inner.isNotEmpty) floorRooms[k.toString()] = inner;
        }
      });
    }
    final rawFloorSchemes = json['floorSchemes'];
    final floorSchemes = <String, String>{};
    if (rawFloorSchemes is Map) {
      rawFloorSchemes.forEach((k, v) {
        if (v is String && v.isNotEmpty) {
          floorSchemes[k.toString()] = v;
        }
      });
    }
    final rawLayers = json['soilLayers'];
    final layers = <SoilLayer>[];
    if (rawLayers is List) {
      for (final l in rawLayers) {
        if (l is Map<String, dynamic>) {
          layers.add(SoilLayer.fromJson(l));
        } else if (l is Map) {
          layers.add(SoilLayer.fromJson(Map<String, dynamic>.from(l)));
        }
      }
    } else if (json['soilType'] is String) {
      // Миграция со старого формата (был один тип грунта без слоёв).
      final t = SoilType.fromName(json['soilType'] as String?);
      if (t != null) layers.add(SoilLayer(type: t));
    }
    final rawBoreholes = json['boreholes'];
    final boreholes = <Borehole>[];
    if (rawBoreholes is List) {
      for (final b in rawBoreholes) {
        if (b is Map<String, dynamic>) {
          boreholes.add(Borehole.fromJson(b));
        } else if (b is Map) {
          boreholes.add(Borehole.fromJson(Map<String, dynamic>.from(b)));
        }
      }
    }
    return ClientBrief(
      region: json['region'] as String?,
      snowZone: json['snowZone'] as int?,
      windZone: json['windZone'] as String?,
      soilLayers: layers,
      groundwaterLevelM: (json['groundwaterLevelM'] as num?)?.toDouble(),
      boreholes: boreholes,
      floors: json['floors'] as int?,
      hasMansard: json['hasMansard'] as bool?,
      hasBasement: json['hasBasement'] as bool?,
      hasGarage: json['hasGarage'] as bool?,
      hasTerrace: json['hasTerrace'] as bool?,
      hasBalcony: json['hasBalcony'] as bool?,
      hasOriel: json['hasOriel'] as bool?,
      hasDoubleHeight: json['hasDoubleHeight'] as bool?,
      hasStaircase: json['hasStaircase'] as bool?,
      targetArea: (json['targetArea'] as num?)?.toDouble(),
      footprintWidth: (json['footprintWidth'] as num?)?.toDouble(),
      footprintLength: (json['footprintLength'] as num?)?.toDouble(),
      rooms: rooms,
      floorRooms: floorRooms,
      wallMaterial: WallMaterial.fromName(json['wallMaterial'] as String?),
      layoutScheme: LayoutScheme.fromName(json['layoutScheme'] as String?),
      floorSchemes: floorSchemes,
      garageSpec: AttachmentSpec.fromJsonOrNull(json['garageSpec']),
      terraceSpec: AttachmentSpec.fromJsonOrNull(json['terraceSpec']),
      planSeed: json['planSeed'] as int?,
      footprintSeed: json['footprintSeed'] as int?,
      specialRequirements: json['specialRequirements'] as String?,
    );
  }
}

/// Тип кровли пристройки (гараж, терраса).
/// Используется для façade-render и геометрии 3D.
enum AttachmentRoofKind {
  flat, // плоская
  shed, // односкатная
  gable, // двускатная
  none; // без кровли (открытая терраса)

  String get title => switch (this) {
        AttachmentRoofKind.flat => 'Плоская',
        AttachmentRoofKind.shed => 'Односкатная',
        AttachmentRoofKind.gable => 'Двускатная',
        AttachmentRoofKind.none => 'Без кровли (открытая)',
      };

  static AttachmentRoofKind fromName(String? n) =>
      AttachmentRoofKind.values.firstWhere(
        (v) => v.name == n,
        orElse: () => AttachmentRoofKind.shed,
      );
}

/// Спецификация пристройки (гараж/терраса) — мини-бриф габаритов
/// и материалов. По п.6 v40 — пользователь выбирает чекбокс «Гараж»
/// или «Терраса» в шаге «Дополнения», а на следующем шаге вводит:
///  • ширину × длину × высоту (м);
///  • тип кровли ([AttachmentRoofKind]);
///  • материал стен ([WallMaterial.name]; для террасы — null
///    означает «открытая, без стен»).
class AttachmentSpec {
  /// Ширина в плане (по короткой стороне), м.
  double width;

  /// Длина в плане (по длинной стороне), м.
  double length;

  /// Высота от пола до карниза, м.
  double height;

  /// Тип кровли.
  AttachmentRoofKind roof;

  /// Материал стен — имя [WallMaterial]. Может быть null
  /// для открытой террасы (без стен).
  String? wallMaterialName;

  AttachmentSpec({
    required this.width,
    required this.length,
    required this.height,
    required this.roof,
    this.wallMaterialName,
  });

  WallMaterial? get wallMaterial =>
      WallMaterial.fromName(wallMaterialName);

  Map<String, dynamic> toJson() => {
        'width': width,
        'length': length,
        'height': height,
        'roof': roof.name,
        'wallMaterial': wallMaterialName,
      };

  static AttachmentSpec? fromJsonOrNull(dynamic raw) {
    if (raw is! Map) return null;
    final w = (raw['width'] as num?)?.toDouble();
    final l = (raw['length'] as num?)?.toDouble();
    final h = (raw['height'] as num?)?.toDouble();
    if (w == null || l == null || h == null) return null;
    return AttachmentSpec(
      width: w,
      length: l,
      height: h,
      roof: AttachmentRoofKind.fromName(raw['roof'] as String?),
      wallMaterialName: raw['wallMaterial'] as String?,
    );
  }

  AttachmentSpec copyWith({
    double? width,
    double? length,
    double? height,
    AttachmentRoofKind? roof,
    String? wallMaterialName,
  }) =>
      AttachmentSpec(
        width: width ?? this.width,
        length: length ?? this.length,
        height: height ?? this.height,
        roof: roof ?? this.roof,
        wallMaterialName: wallMaterialName ?? this.wallMaterialName,
      );

  /// Дефолт для гаража — 6×4×2.7 м, односкатная, тот же материал стен,
  /// что у дома (если он задан).
  static AttachmentSpec defaultGarage(WallMaterial? wall) => AttachmentSpec(
        width: 4.0,
        length: 6.0,
        height: 2.7,
        roof: AttachmentRoofKind.shed,
        wallMaterialName: wall?.name,
      );

  /// Дефолт для террасы — 4×2×0.3 м (без кровли = открытая, без стен).
  static AttachmentSpec defaultTerrace() => AttachmentSpec(
        width: 4.0,
        length: 2.0,
        height: 0.3,
        roof: AttachmentRoofKind.none,
        wallMaterialName: null,
      );
}
