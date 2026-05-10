/// Конфигурация дома — полная параметризация для генерации планировки.
///
/// Описывает ВСЕ настраиваемые параметры дома: от общих характеристик
/// (площадь, этажность) до детальных (вид плитки в каждом санузле,
/// тип карниза, материал подоконника). Любой параметр может быть
/// изменён алгоритмом или пользователем.
library;

import '../../data/wall_materials.dart';

// ---------------------------------------------------------------------------
// Общие параметры дома
// ---------------------------------------------------------------------------

/// Форма здания в плане.
enum BuildingShape {
  rectangular,
  lShape,
  tShape,
  uShape,
  plusShape,
  custom,
}

/// Стиль архитектуры.
enum ArchitecturalStyle {
  modern,
  classic,
  scandinavian,
  minimalist,
  barnhouse,
  chalet,
  hitech,
  craftsman,
  colonial,
  mediterranean,
  rustic,
}

/// Тип фундамента.
enum FoundationType {
  slab,
  strip,
  pile,
  pileWithGrillage,
  combined,
}

/// Тип крыши.
enum RoofType {
  gable,
  hip,
  flat,
  mansard,
  shed,
  gambrel,
  combined,
  butterfly,
}

/// Материал кровли.
enum RoofingMaterial {
  metalTile,
  softBitumen,
  ceramicTile,
  slate,
  profileSheet,
  seamMetal,
  membrane,
  greenRoof,
}

/// Тип лестницы.
enum StaircaseType {
  straight,
  lShaped,
  uShaped,
  spiral,
  winder,
}

/// Материал лестницы.
enum StaircaseMaterial {
  wood,
  metal,
  concrete,
  combined,
  glass,
}

/// Тип отопления.
enum HeatingSystem {
  gasBoiler,
  electricBoiler,
  heatPump,
  solidFuelBoiler,
  underfloorElectric,
  underfloorWater,
  radiators,
  combined,
}

/// Тип водоснабжения.
enum WaterSupplyType {
  central,
  well,
  borehole,
  combined,
}

/// Тип канализации.
enum SewerageType {
  central,
  septicTank,
  bioStation,
  cesspool,
}

/// Тип вентиляции.
enum VentilationType {
  natural,
  mechanical,
  supplyExhaust,
  recuperation,
}

/// Тип электроснабжения.
enum ElectricalSystem {
  singlePhase,
  threePhase,
}

// ---------------------------------------------------------------------------
// Параметры фасада
// ---------------------------------------------------------------------------

/// Материал отделки фасада.
enum FacadeMaterial {
  brick,
  plaster,
  stone,
  woodSiding,
  vinylSiding,
  fiberCement,
  ceramicPanels,
  hpl,
  combinedBrickPlaster,
  combinedStoneWood,
}

/// Конфигурация фасада.
class FacadeConfig {
  FacadeMaterial primaryMaterial;
  FacadeMaterial? accentMaterial;

  /// Цвет фасада (hex).
  String primaryColor;
  String? accentColor;

  /// Тип цоколя.
  String basementFinish; // 'stone', 'plaster', 'brick', 'panels'

  /// Высота цоколя, м.
  double basementHeight;

  /// Наличие декоративных элементов.
  bool hasCornice;
  bool hasPilasters;
  bool hasBalustrade;

  FacadeConfig({
    this.primaryMaterial = FacadeMaterial.plaster,
    this.accentMaterial,
    this.primaryColor = '#F5F0E8',
    this.accentColor,
    this.basementFinish = 'stone',
    this.basementHeight = 0.5,
    this.hasCornice = false,
    this.hasPilasters = false,
    this.hasBalustrade = false,
  });

  Map<String, dynamic> toJson() => {
        'primaryMaterial': primaryMaterial.name,
        'accentMaterial': accentMaterial?.name,
        'primaryColor': primaryColor,
        'accentColor': accentColor,
        'basementFinish': basementFinish,
        'basementHeight': basementHeight,
        'hasCornice': hasCornice,
        'hasPilasters': hasPilasters,
        'hasBalustrade': hasBalustrade,
      };

  static FacadeConfig fromJson(Map<String, dynamic> j) {
    return FacadeConfig(
      primaryMaterial:
          _enumFromName(FacadeMaterial.values, j['primaryMaterial'] as String?)
              ?? FacadeMaterial.plaster,
      accentMaterial:
          _enumFromName(FacadeMaterial.values, j['accentMaterial'] as String?),
      primaryColor: j['primaryColor'] as String? ?? '#F5F0E8',
      accentColor: j['accentColor'] as String?,
      basementFinish: j['basementFinish'] as String? ?? 'stone',
      basementHeight: (j['basementHeight'] as num?)?.toDouble() ?? 0.5,
      hasCornice: j['hasCornice'] as bool? ?? false,
      hasPilasters: j['hasPilasters'] as bool? ?? false,
      hasBalustrade: j['hasBalustrade'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Конфигурация комнаты (детальная отделка)
// ---------------------------------------------------------------------------

/// Детальные параметры отделки одной комнаты.
class RoomFinishConfig {
  /// ID комнаты (ссылка на PlanRoom).
  String roomId;

  /// Тип комнаты.
  String roomKind;

  // -- Пол --
  String? flooringId;
  String? flooringColor;
  bool hasUnderfloorHeating;
  String? plinthMaterial; // 'plastic', 'mdf', 'wood', 'ceramic', 'aluminum'
  double plinthHeightMm;

  // -- Стены --
  String? wallFinishId;
  String? wallColor;
  String? accentWallFinishId;
  int accentWallIndex; // 0..3 — какая стена акцентная (-1 = нет)

  // -- Потолок --
  String? ceilingId;
  double ceilingHeightM;
  bool hasSpotLights;
  bool hasChandelier;
  bool hasLedStrip;

  // -- Окна --
  String? windowProfileId;
  String windowSillMaterial; // 'pvc', 'stone', 'wood', 'composite'
  double windowSillDepthMm;

  // -- Дверь --
  String doorMaterial; // 'mdf', 'massif', 'glass', 'steel'
  String doorColor;
  String doorHandleType; // 'lever', 'knob', 'push'

  // -- Электрика --
  int socketCount;
  int switchCount;
  bool hasSmartHome;

  RoomFinishConfig({
    required this.roomId,
    required this.roomKind,
    this.flooringId,
    this.flooringColor,
    this.hasUnderfloorHeating = false,
    this.plinthMaterial = 'plastic',
    this.plinthHeightMm = 60,
    this.wallFinishId,
    this.wallColor,
    this.accentWallFinishId,
    this.accentWallIndex = -1,
    this.ceilingId,
    this.ceilingHeightM = 2.7,
    this.hasSpotLights = false,
    this.hasChandelier = false,
    this.hasLedStrip = false,
    this.windowProfileId,
    this.windowSillMaterial = 'pvc',
    this.windowSillDepthMm = 250,
    this.doorMaterial = 'mdf',
    this.doorColor = '#FFFFFF',
    this.doorHandleType = 'lever',
    this.socketCount = 3,
    this.switchCount = 1,
    this.hasSmartHome = false,
  });

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'roomKind': roomKind,
        'flooringId': flooringId,
        'flooringColor': flooringColor,
        'hasUnderfloorHeating': hasUnderfloorHeating,
        'plinthMaterial': plinthMaterial,
        'plinthHeightMm': plinthHeightMm,
        'wallFinishId': wallFinishId,
        'wallColor': wallColor,
        'accentWallFinishId': accentWallFinishId,
        'accentWallIndex': accentWallIndex,
        'ceilingId': ceilingId,
        'ceilingHeightM': ceilingHeightM,
        'hasSpotLights': hasSpotLights,
        'hasChandelier': hasChandelier,
        'hasLedStrip': hasLedStrip,
        'windowProfileId': windowProfileId,
        'windowSillMaterial': windowSillMaterial,
        'windowSillDepthMm': windowSillDepthMm,
        'doorMaterial': doorMaterial,
        'doorColor': doorColor,
        'doorHandleType': doorHandleType,
        'socketCount': socketCount,
        'switchCount': switchCount,
        'hasSmartHome': hasSmartHome,
      };

  static RoomFinishConfig fromJson(Map<String, dynamic> j) {
    return RoomFinishConfig(
      roomId: j['roomId'] as String? ?? '',
      roomKind: j['roomKind'] as String? ?? '',
      flooringId: j['flooringId'] as String?,
      flooringColor: j['flooringColor'] as String?,
      hasUnderfloorHeating: j['hasUnderfloorHeating'] as bool? ?? false,
      plinthMaterial: j['plinthMaterial'] as String? ?? 'plastic',
      plinthHeightMm: (j['plinthHeightMm'] as num?)?.toDouble() ?? 60,
      wallFinishId: j['wallFinishId'] as String?,
      wallColor: j['wallColor'] as String?,
      accentWallFinishId: j['accentWallFinishId'] as String?,
      accentWallIndex: j['accentWallIndex'] as int? ?? -1,
      ceilingId: j['ceilingId'] as String?,
      ceilingHeightM: (j['ceilingHeightM'] as num?)?.toDouble() ?? 2.7,
      hasSpotLights: j['hasSpotLights'] as bool? ?? false,
      hasChandelier: j['hasChandelier'] as bool? ?? false,
      hasLedStrip: j['hasLedStrip'] as bool? ?? false,
      windowProfileId: j['windowProfileId'] as String?,
      windowSillMaterial: j['windowSillMaterial'] as String? ?? 'pvc',
      windowSillDepthMm: (j['windowSillDepthMm'] as num?)?.toDouble() ?? 250,
      doorMaterial: j['doorMaterial'] as String? ?? 'mdf',
      doorColor: j['doorColor'] as String? ?? '#FFFFFF',
      doorHandleType: j['doorHandleType'] as String? ?? 'lever',
      socketCount: j['socketCount'] as int? ?? 3,
      switchCount: j['switchCount'] as int? ?? 1,
      hasSmartHome: j['hasSmartHome'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Главная конфигурация дома (корневой объект модуля)
// ---------------------------------------------------------------------------

/// Полная конфигурация дома для генерации планировки.
///
/// Любой параметр может быть задан пользователем или подобран
/// алгоритмом. `null`-значения означают «автовыбор».
class HouseLayoutConfig {
  // -- Общие параметры --
  String? name;
  double? totalArea; // м²
  int floors; // 1..3
  bool hasMansard;
  bool hasBasement;
  BuildingShape shape;
  ArchitecturalStyle style;

  // -- Габариты --
  double? footprintWidth; // м
  double? footprintLength; // м
  double floorHeight; // м (от пола до пола)
  double firstFloorHeight; // м

  // -- Конструктив --
  WallMaterial wallMaterial;
  double? wallThicknessMm;
  double? partitionThicknessMm; // внутренние перегородки
  FoundationType? foundationType;
  RoofType? roofType;
  double? roofSlopeAngle; // градусы
  RoofingMaterial? roofingMaterial;

  // -- Фасад --
  FacadeConfig facade;

  // -- Лестница --
  StaircaseType? staircaseType;
  StaircaseMaterial? staircaseMaterial;

  // -- Инженерные системы --
  HeatingSystem? heating;
  WaterSupplyType? waterSupply;
  SewerageType? sewerage;
  VentilationType? ventilation;
  ElectricalSystem? electrical;

  // -- Дополнительные элементы --
  bool hasGarage;
  double? garageWidth;
  double? garageLength;
  bool hasTerrace;
  double? terraceWidth;
  double? terraceLength;
  bool hasBalcony;
  bool hasPorch;
  double? porchWidth;
  double? porchDepth;

  // -- Комнаты и отделка --
  /// Состав комнат: roomKind → количество.
  Map<String, int> rooms;

  /// Детальная отделка каждой комнаты (заполняется после генерации
  /// плана или вручную пользователем).
  List<RoomFinishConfig> roomFinishes;

  // -- Внешняя территория --
  bool hasFence;
  String? fenceMaterial; // 'metal', 'wood', 'brick', 'combined'
  double? fenceHeight;
  bool hasGate;
  bool hasParking;
  int parkingSpots;

  HouseLayoutConfig({
    this.name,
    this.totalArea,
    this.floors = 1,
    this.hasMansard = false,
    this.hasBasement = false,
    this.shape = BuildingShape.rectangular,
    this.style = ArchitecturalStyle.modern,
    this.footprintWidth,
    this.footprintLength,
    this.floorHeight = 3.0,
    this.firstFloorHeight = 3.0,
    this.wallMaterial = WallMaterial.aerated,
    this.wallThicknessMm,
    this.partitionThicknessMm,
    this.foundationType,
    this.roofType,
    this.roofSlopeAngle,
    this.roofingMaterial,
    FacadeConfig? facade,
    this.staircaseType,
    this.staircaseMaterial,
    this.heating,
    this.waterSupply,
    this.sewerage,
    this.ventilation,
    this.electrical,
    this.hasGarage = false,
    this.garageWidth,
    this.garageLength,
    this.hasTerrace = false,
    this.terraceWidth,
    this.terraceLength,
    this.hasBalcony = false,
    this.hasPorch = true,
    this.porchWidth,
    this.porchDepth,
    Map<String, int>? rooms,
    List<RoomFinishConfig>? roomFinishes,
    this.hasFence = false,
    this.fenceMaterial,
    this.fenceHeight,
    this.hasGate = false,
    this.hasParking = false,
    this.parkingSpots = 1,
  })  : facade = facade ?? FacadeConfig(),
        rooms = rooms ?? <String, int>{},
        roomFinishes = roomFinishes ?? <RoomFinishConfig>[];

  Map<String, dynamic> toJson() => {
        'name': name,
        'totalArea': totalArea,
        'floors': floors,
        'hasMansard': hasMansard,
        'hasBasement': hasBasement,
        'shape': shape.name,
        'style': style.name,
        'footprintWidth': footprintWidth,
        'footprintLength': footprintLength,
        'floorHeight': floorHeight,
        'firstFloorHeight': firstFloorHeight,
        'wallMaterial': wallMaterial.name,
        'wallThicknessMm': wallThicknessMm,
        'partitionThicknessMm': partitionThicknessMm,
        'foundationType': foundationType?.name,
        'roofType': roofType?.name,
        'roofSlopeAngle': roofSlopeAngle,
        'roofingMaterial': roofingMaterial?.name,
        'facade': facade.toJson(),
        'staircaseType': staircaseType?.name,
        'staircaseMaterial': staircaseMaterial?.name,
        'heating': heating?.name,
        'waterSupply': waterSupply?.name,
        'sewerage': sewerage?.name,
        'ventilation': ventilation?.name,
        'electrical': electrical?.name,
        'hasGarage': hasGarage,
        'garageWidth': garageWidth,
        'garageLength': garageLength,
        'hasTerrace': hasTerrace,
        'terraceWidth': terraceWidth,
        'terraceLength': terraceLength,
        'hasBalcony': hasBalcony,
        'hasPorch': hasPorch,
        'porchWidth': porchWidth,
        'porchDepth': porchDepth,
        'rooms': rooms,
        if (roomFinishes.isNotEmpty)
          'roomFinishes': roomFinishes.map((f) => f.toJson()).toList(),
        'hasFence': hasFence,
        'fenceMaterial': fenceMaterial,
        'fenceHeight': fenceHeight,
        'hasGate': hasGate,
        'hasParking': hasParking,
        'parkingSpots': parkingSpots,
      };

  static HouseLayoutConfig fromJson(Map<String, dynamic> j) {
    final roomFinishesJson = j['roomFinishes'];
    final finishes = <RoomFinishConfig>[];
    if (roomFinishesJson is List) {
      for (final f in roomFinishesJson) {
        if (f is Map<String, dynamic>) {
          finishes.add(RoomFinishConfig.fromJson(f));
        }
      }
    }
    final roomsRaw = j['rooms'];
    final rooms = <String, int>{};
    if (roomsRaw is Map) {
      for (final e in roomsRaw.entries) {
        rooms[e.key.toString()] = (e.value as num).toInt();
      }
    }

    return HouseLayoutConfig(
      name: j['name'] as String?,
      totalArea: (j['totalArea'] as num?)?.toDouble(),
      floors: j['floors'] as int? ?? 1,
      hasMansard: j['hasMansard'] as bool? ?? false,
      hasBasement: j['hasBasement'] as bool? ?? false,
      shape: _enumFromName(BuildingShape.values, j['shape'] as String?)
          ?? BuildingShape.rectangular,
      style: _enumFromName(ArchitecturalStyle.values, j['style'] as String?)
          ?? ArchitecturalStyle.modern,
      footprintWidth: (j['footprintWidth'] as num?)?.toDouble(),
      footprintLength: (j['footprintLength'] as num?)?.toDouble(),
      floorHeight: (j['floorHeight'] as num?)?.toDouble() ?? 3.0,
      firstFloorHeight: (j['firstFloorHeight'] as num?)?.toDouble() ?? 3.0,
      wallMaterial:
          WallMaterial.fromName(j['wallMaterial'] as String?) ?? WallMaterial.aerated,
      wallThicknessMm: (j['wallThicknessMm'] as num?)?.toDouble(),
      partitionThicknessMm: (j['partitionThicknessMm'] as num?)?.toDouble(),
      foundationType:
          _enumFromName(FoundationType.values, j['foundationType'] as String?),
      roofType:
          _enumFromName(RoofType.values, j['roofType'] as String?),
      roofSlopeAngle: (j['roofSlopeAngle'] as num?)?.toDouble(),
      roofingMaterial:
          _enumFromName(RoofingMaterial.values, j['roofingMaterial'] as String?),
      facade: j['facade'] is Map<String, dynamic>
          ? FacadeConfig.fromJson(j['facade'] as Map<String, dynamic>)
          : null,
      staircaseType:
          _enumFromName(StaircaseType.values, j['staircaseType'] as String?),
      staircaseMaterial:
          _enumFromName(StaircaseMaterial.values, j['staircaseMaterial'] as String?),
      heating:
          _enumFromName(HeatingSystem.values, j['heating'] as String?),
      waterSupply:
          _enumFromName(WaterSupplyType.values, j['waterSupply'] as String?),
      sewerage:
          _enumFromName(SewerageType.values, j['sewerage'] as String?),
      ventilation:
          _enumFromName(VentilationType.values, j['ventilation'] as String?),
      electrical:
          _enumFromName(ElectricalSystem.values, j['electrical'] as String?),
      hasGarage: j['hasGarage'] as bool? ?? false,
      garageWidth: (j['garageWidth'] as num?)?.toDouble(),
      garageLength: (j['garageLength'] as num?)?.toDouble(),
      hasTerrace: j['hasTerrace'] as bool? ?? false,
      terraceWidth: (j['terraceWidth'] as num?)?.toDouble(),
      terraceLength: (j['terraceLength'] as num?)?.toDouble(),
      hasBalcony: j['hasBalcony'] as bool? ?? false,
      hasPorch: j['hasPorch'] as bool? ?? true,
      porchWidth: (j['porchWidth'] as num?)?.toDouble(),
      porchDepth: (j['porchDepth'] as num?)?.toDouble(),
      rooms: rooms,
      roomFinishes: finishes,
      hasFence: j['hasFence'] as bool? ?? false,
      fenceMaterial: j['fenceMaterial'] as String?,
      fenceHeight: (j['fenceHeight'] as num?)?.toDouble(),
      hasGate: j['hasGate'] as bool? ?? false,
      hasParking: j['hasParking'] as bool? ?? false,
      parkingSpots: j['parkingSpots'] as int? ?? 1,
    );
  }
}

T? _enumFromName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
