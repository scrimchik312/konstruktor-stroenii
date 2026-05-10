/// Автоконфигуратор — подбирает оптимальные параметры дома.
///
/// На основе заданных пользователем ключевых параметров (площадь, этажность,
/// бюджет) алгоритм заполняет все остальные параметры конфигурации:
/// состав комнат, габариты пятна, материалы, инженерные системы,
/// отделку и прочее.
library;

import 'dart:math' as math;

import '../../data/house_layout/finishing_catalog.dart';
import '../../data/house_layout/planning_rules.dart';
import '../../data/wall_materials.dart';
import '../../models/house_layout/house_config.dart';

/// Автоконфигуратор дома.
class HouseAutoConfigurator {
  const HouseAutoConfigurator();

  /// Заполняет все `null`-поля конфигурации оптимальными значениями.
  ///
  /// Не перезаписывает поля, уже заданные пользователем.
  HouseLayoutConfig configure(HouseLayoutConfig config) {
    _configureRooms(config);
    _configureFootprint(config);
    _configureStructure(config);
    _configureRoof(config);
    _configureFacade(config);
    _configureEngineering(config);
    _configureStaircase(config);
    _configureAttachments(config);
    _configureFinishes(config);
    return config;
  }

  /// Подбирает состав комнат по площади дома.
  void _configureRooms(HouseLayoutConfig config) {
    if (config.rooms.isNotEmpty) return;

    final area = config.totalArea ?? _estimateArea(config);
    final category = houseSizeCategory(area);
    final recommended = kRecommendedRoomsBySize[category];
    if (recommended != null) {
      config.rooms.addAll(recommended);
    }
  }

  /// Подбирает габариты пятна застройки.
  void _configureFootprint(HouseLayoutConfig config) {
    if (config.footprintWidth != null && config.footprintLength != null) return;

    final totalArea = config.totalArea ?? _estimateArea(config);
    final floors = config.floors;
    final floorArea = totalArea / floors;

    // Подбираем соотношение сторон близко к золотому сечению.
    final w = math.sqrt(floorArea / ProportionRule.goldenRatio);
    final l = w * ProportionRule.goldenRatio;

    // Округление до 0.5 м (строительный модуль).
    config.footprintWidth ??= (w * 2).roundToDouble() / 2;
    config.footprintLength ??= (l * 2).roundToDouble() / 2;
  }

  /// Подбирает конструктив.
  void _configureStructure(HouseLayoutConfig config) {
    // Толщина стен по материалу.
    config.wallThicknessMm ??= _wallThickness(config.wallMaterial);
    config.partitionThicknessMm ??= _partitionThickness(config.wallMaterial);

    // Фундамент.
    config.foundationType ??= _selectFoundation(config);
  }

  /// Подбирает крышу.
  void _configureRoof(HouseLayoutConfig config) {
    if (config.roofType == null) {
      if (config.hasMansard) {
        config.roofType = RoofType.mansard;
      } else if (config.style == ArchitecturalStyle.modern ||
          config.style == ArchitecturalStyle.hitech) {
        config.roofType = RoofType.flat;
      } else {
        config.roofType = RoofType.gable;
      }
    }

    config.roofSlopeAngle ??= _roofSlope(config.roofType!);
    config.roofingMaterial ??= _selectRoofing(config.roofType!);
  }

  /// Настраивает фасад в зависимости от стиля.
  void _configureFacade(HouseLayoutConfig config) {
    final facade = config.facade;

    switch (config.style) {
      case ArchitecturalStyle.modern:
      case ArchitecturalStyle.hitech:
        facade.primaryMaterial = FacadeMaterial.plaster;
        facade.primaryColor = '#F5F0E8';
        facade.hasCornice = false;
      case ArchitecturalStyle.classic:
        facade.primaryMaterial = FacadeMaterial.brick;
        facade.primaryColor = '#D4A574';
        facade.hasCornice = true;
        facade.hasPilasters = true;
      case ArchitecturalStyle.scandinavian:
        facade.primaryMaterial = FacadeMaterial.woodSiding;
        facade.primaryColor = '#8B7355';
      case ArchitecturalStyle.minimalist:
        facade.primaryMaterial = FacadeMaterial.plaster;
        facade.primaryColor = '#FFFFFF';
      case ArchitecturalStyle.barnhouse:
        facade.primaryMaterial = FacadeMaterial.woodSiding;
        facade.primaryColor = '#3C3C3C';
      case ArchitecturalStyle.chalet:
        facade.primaryMaterial = FacadeMaterial.combinedStoneWood;
        facade.primaryColor = '#A0522D';
        facade.hasBalustrade = true;
      case ArchitecturalStyle.craftsman:
        facade.primaryMaterial = FacadeMaterial.combinedBrickPlaster;
        facade.primaryColor = '#C9B58E';
        facade.hasCornice = true;
      case ArchitecturalStyle.colonial:
        facade.primaryMaterial = FacadeMaterial.brick;
        facade.primaryColor = '#8B4513';
        facade.hasPilasters = true;
      case ArchitecturalStyle.mediterranean:
        facade.primaryMaterial = FacadeMaterial.plaster;
        facade.primaryColor = '#FAEBD7';
        facade.hasBalustrade = true;
      case ArchitecturalStyle.rustic:
        facade.primaryMaterial = FacadeMaterial.woodSiding;
        facade.primaryColor = '#6B4226';
    }
  }

  /// Подбирает инженерные системы.
  void _configureEngineering(HouseLayoutConfig config) {
    config.heating ??= HeatingSystem.gasBoiler;
    config.waterSupply ??= WaterSupplyType.central;
    config.sewerage ??= SewerageType.septicTank;
    config.ventilation ??= VentilationType.natural;
    config.electrical ??= ElectricalSystem.singlePhase;

    // Большие дома — трёхфазное подключение.
    final area = config.totalArea ?? 100;
    if (area > 200) {
      config.electrical = ElectricalSystem.threePhase;
    }

    // Если есть рекуперация — значит, приточно-вытяжная.
    if (config.style == ArchitecturalStyle.modern ||
        config.style == ArchitecturalStyle.hitech) {
      config.ventilation = VentilationType.supplyExhaust;
    }
  }

  /// Подбирает лестницу.
  void _configureStaircase(HouseLayoutConfig config) {
    if (config.floors < 2 && !config.hasMansard && !config.hasBasement) return;

    if (config.staircaseType == null) {
      final area = config.totalArea ?? 100;
      if (area < 80) {
        config.staircaseType = StaircaseType.spiral;
      } else if (area < 150) {
        config.staircaseType = StaircaseType.lShaped;
      } else {
        config.staircaseType = StaircaseType.uShaped;
      }
    }

    config.staircaseMaterial ??= StaircaseMaterial.wood;
  }

  /// Подбирает пристройки (крыльцо, терраса, гараж).
  void _configureAttachments(HouseLayoutConfig config) {
    if (config.hasPorch) {
      config.porchWidth ??= 2.0;
      config.porchDepth ??= 1.5;
    }
    if (config.hasGarage) {
      config.garageWidth ??= 4.0;
      config.garageLength ??= 6.0;
    }
    if (config.hasTerrace) {
      config.terraceWidth ??= 4.0;
      config.terraceLength ??= 3.0;
    }
  }

  /// Подбирает финишную отделку для каждой комнаты.
  void _configureFinishes(HouseLayoutConfig config) {
    if (config.roomFinishes.isNotEmpty) return;

    config.rooms.forEach((kind, count) {
      for (var i = 0; i < count; i++) {
        config.roomFinishes.add(_defaultFinish(kind, i));
      }
    });
  }

  /// Возвращает отделку по умолчанию для типа комнаты.
  RoomFinishConfig _defaultFinish(String roomKind, int index) {
    final finish = RoomFinishConfig(
      roomId: '${roomKind}_$index',
      roomKind: roomKind,
    );

    // Напольное покрытие.
    final flooring = kFlooringCatalog.where(
      (f) => f.suitableRooms.contains(roomKind),
    );
    if (flooring.isNotEmpty) {
      finish.flooringId = flooring.first.id;
    }

    // Настенное покрытие.
    final wallFinish = kWallFinishCatalog.where(
      (w) => w.suitableRooms.contains(roomKind),
    );
    if (wallFinish.isNotEmpty) {
      finish.wallFinishId = wallFinish.first.id;
    }

    // Потолок.
    final ceiling = kCeilingCatalog.where(
      (c) => c.suitableRooms.contains(roomKind),
    );
    if (ceiling.isNotEmpty) {
      finish.ceilingId = ceiling.first.id;
    }

    // Тёплый пол в санузлах.
    if (roomKind == 'bathroom' || roomKind == 'masterBathroom') {
      finish.hasUnderfloorHeating = true;
    }

    // Количество розеток по типу комнаты.
    finish.socketCount = _defaultSocketCount(roomKind);
    finish.switchCount = _defaultSwitchCount(roomKind);

    return finish;
  }

  // -- Вспомогательные методы --

  double _estimateArea(HouseLayoutConfig config) {
    // Если площадь не задана, оцениваем по составу комнат.
    if (config.rooms.isEmpty) return 100; // fallback

    var area = 0.0;
    config.rooms.forEach((kind, count) {
      final standard = kRoomAreaStandards[kind];
      area += (standard?.recommendedArea ?? 10) * count;
    });
    // Добавляем 20% на коридоры и стены.
    return area * 1.20;
  }

  double _wallThickness(WallMaterial material) {
    switch (material) {
      case WallMaterial.brick:
        return 510;
      case WallMaterial.aerated:
        return 400;
      case WallMaterial.expandedClay:
        return 400;
      case WallMaterial.timber:
        return 200;
      case WallMaterial.frame:
        return 150;
    }
  }

  double _partitionThickness(WallMaterial material) {
    switch (material) {
      case WallMaterial.brick:
        return 120;
      case WallMaterial.aerated:
        return 100;
      case WallMaterial.expandedClay:
        return 100;
      case WallMaterial.timber:
        return 100;
      case WallMaterial.frame:
        return 100;
    }
  }

  FoundationType _selectFoundation(HouseLayoutConfig config) {
    final floors = config.floors;
    final material = config.wallMaterial;

    // Тяжёлые стены + 2+ этажа → ленточный.
    if ((material == WallMaterial.brick ||
            material == WallMaterial.expandedClay) &&
        floors >= 2) {
      return FoundationType.strip;
    }

    // Лёгкие стены → сваи с ростверком.
    if (material == WallMaterial.frame || material == WallMaterial.timber) {
      return FoundationType.pileWithGrillage;
    }

    // Одноэтажный газобетон → плита.
    if (material == WallMaterial.aerated && floors == 1) {
      return FoundationType.slab;
    }

    return FoundationType.strip;
  }

  double _roofSlope(RoofType type) {
    switch (type) {
      case RoofType.gable:
        return 30;
      case RoofType.hip:
        return 25;
      case RoofType.flat:
        return 3;
      case RoofType.mansard:
        return 60;
      case RoofType.shed:
        return 15;
      case RoofType.gambrel:
        return 45;
      case RoofType.combined:
        return 30;
      case RoofType.butterfly:
        return 20;
    }
  }

  RoofingMaterial _selectRoofing(RoofType type) {
    switch (type) {
      case RoofType.flat:
        return RoofingMaterial.membrane;
      case RoofType.mansard:
        return RoofingMaterial.softBitumen;
      case RoofType.gable:
      case RoofType.hip:
      case RoofType.combined:
        return RoofingMaterial.metalTile;
      case RoofType.shed:
      case RoofType.gambrel:
      case RoofType.butterfly:
        return RoofingMaterial.profileSheet;
    }
  }

  int _defaultSocketCount(String roomKind) {
    switch (roomKind) {
      case 'kitchen':
      case 'kitchenDining':
        return 8;
      case 'livingRoom':
        return 6;
      case 'bedroom':
      case 'masterBedroom':
      case 'kidsRoom':
        return 4;
      case 'study':
        return 6;
      case 'bathroom':
      case 'masterBathroom':
        return 2;
      case 'hallway':
      case 'corridor':
        return 2;
      case 'boilerRoom':
        return 3;
      case 'garage':
        return 4;
      case 'laundry':
        return 3;
      default:
        return 2;
    }
  }

  int _defaultSwitchCount(String roomKind) {
    switch (roomKind) {
      case 'livingRoom':
      case 'kitchen':
      case 'kitchenDining':
        return 2;
      case 'corridor':
      case 'hallway':
        return 2; // проходной выключатель
      default:
        return 1;
    }
  }
}
