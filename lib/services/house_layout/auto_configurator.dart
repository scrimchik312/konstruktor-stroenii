/// Автоконфигуратор — самодостаточная копия.
library;

import 'dart:math' as math;

import '../../data/house_layout/planning_rules.dart';
import '../../models/house_layout/house_config.dart';

class HouseAutoConfigurator {
  const HouseAutoConfigurator();

  HouseLayoutConfig configure(HouseLayoutConfig config) {
    _configureRooms(config);
    _configureFootprint(config);
    _configureStructure(config);
    _configureRoof(config);
    _configureFacade(config);
    _configureEngineering(config);
    _configureStaircase(config);
    _configureAttachments(config);
    return config;
  }

  void _configureRooms(HouseLayoutConfig config) {
    if (config.rooms.isNotEmpty) return;
    final area = config.totalArea ?? _estimateArea(config);
    final category = houseSizeCategory(area);
    final recommended = kRecommendedRoomsBySize[category];
    if (recommended != null) config.rooms.addAll(recommended);

    // Add corridor if category rules require it
    final catRules = kCategoryRules[category];
    if (catRules != null && catRules.requiresCorridor && !config.rooms.containsKey('corridor')) {
      config.rooms['corridor'] = 1;
    }
  }

  void _configureFootprint(HouseLayoutConfig config) {
    if (config.footprintWidth != null && config.footprintLength != null) return;
    final totalArea = config.totalArea ?? _estimateArea(config);
    final floorArea = totalArea / config.floors;
    final w = math.sqrt(floorArea / ProportionRule.goldenRatio);
    final l = w * ProportionRule.goldenRatio;
    config.footprintWidth ??= (w * 2).roundToDouble() / 2;
    config.footprintLength ??= (l * 2).roundToDouble() / 2;
  }

  void _configureStructure(HouseLayoutConfig config) {
    config.wallThicknessMm ??= _wallThickness(config.wallMaterial);
    config.partitionThicknessMm ??= _partitionThickness(config.wallMaterial);
    config.foundationType ??= _selectFoundation(config);
  }

  void _configureRoof(HouseLayoutConfig config) {
    if (config.roofType == null) {
      if (config.hasMansard) {
        config.roofType = RoofType.mansard;
      } else if (config.style == ArchitecturalStyle.modern || config.style == ArchitecturalStyle.hitech) {
        config.roofType = RoofType.flat;
      } else {
        config.roofType = RoofType.gable;
      }
    }
    config.roofSlopeAngle ??= _roofSlope(config.roofType!);
    config.roofingMaterial ??= _selectRoofing(config.roofType!);
  }

  void _configureFacade(HouseLayoutConfig config) {
    final f = config.facade;
    switch (config.style) {
      case ArchitecturalStyle.modern:
      case ArchitecturalStyle.hitech:
        f.primaryMaterial = FacadeMaterial.plaster;
        f.primaryColor = '#F5F0E8';
      case ArchitecturalStyle.classic:
        f.primaryMaterial = FacadeMaterial.brick;
        f.primaryColor = '#D4A574';
        f.hasCornice = true;
        f.hasPilasters = true;
      case ArchitecturalStyle.scandinavian:
        f.primaryMaterial = FacadeMaterial.woodSiding;
        f.primaryColor = '#8B7355';
      case ArchitecturalStyle.minimalist:
        f.primaryMaterial = FacadeMaterial.plaster;
        f.primaryColor = '#FFFFFF';
      case ArchitecturalStyle.barnhouse:
        f.primaryMaterial = FacadeMaterial.woodSiding;
        f.primaryColor = '#3C3C3C';
      case ArchitecturalStyle.chalet:
        f.primaryMaterial = FacadeMaterial.combinedStoneWood;
        f.primaryColor = '#A0522D';
        f.hasBalustrade = true;
      case ArchitecturalStyle.craftsman:
        f.primaryMaterial = FacadeMaterial.combinedBrickPlaster;
        f.primaryColor = '#C9B58E';
        f.hasCornice = true;
      case ArchitecturalStyle.colonial:
        f.primaryMaterial = FacadeMaterial.brick;
        f.primaryColor = '#8B4513';
        f.hasPilasters = true;
      case ArchitecturalStyle.mediterranean:
        f.primaryMaterial = FacadeMaterial.plaster;
        f.primaryColor = '#FAEBD7';
        f.hasBalustrade = true;
      case ArchitecturalStyle.rustic:
        f.primaryMaterial = FacadeMaterial.woodSiding;
        f.primaryColor = '#6B4226';
    }
  }

  void _configureEngineering(HouseLayoutConfig config) {
    config.heating ??= HeatingSystem.gasBoiler;
    config.waterSupply ??= WaterSupplyType.central;
    config.sewerage ??= SewerageType.septicTank;
    config.ventilation ??= VentilationType.natural;
    config.electrical ??= ElectricalSystem.singlePhase;
    final area = config.totalArea ?? 100;
    if (area > 200) config.electrical = ElectricalSystem.threePhase;
    if (config.style == ArchitecturalStyle.modern || config.style == ArchitecturalStyle.hitech) {
      config.ventilation = VentilationType.supplyExhaust;
    }
  }

  void _configureStaircase(HouseLayoutConfig config) {
    if (config.floors < 2 && !config.hasMansard && !config.hasBasement) return;
    if (config.staircaseType == null) {
      final area = config.totalArea ?? 100;
      if (area < 80) { config.staircaseType = StaircaseType.spiral; }
      else if (area < 150) { config.staircaseType = StaircaseType.lShaped; }
      else { config.staircaseType = StaircaseType.uShaped; }
    }
    config.staircaseMaterial ??= StaircaseMaterial.wood;
  }

  void _configureAttachments(HouseLayoutConfig config) {
    if (config.hasPorch) { config.porchWidth ??= 2.0; config.porchDepth ??= 1.5; }
    if (config.hasGarage) { config.garageWidth ??= 4.0; config.garageLength ??= 6.0; }
    if (config.hasTerrace) { config.terraceWidth ??= 4.0; config.terraceLength ??= 3.0; }
  }

  double _estimateArea(HouseLayoutConfig config) {
    if (config.rooms.isEmpty) return 100;
    var area = 0.0;
    config.rooms.forEach((kind, count) {
      final standard = kRoomAreaStandards[kind];
      area += (standard?.recommendedArea ?? 10) * count;
    });
    return area * 1.20;
  }

  double _wallThickness(WallMaterial m) {
    switch (m) {
      case WallMaterial.brick: return 510;
      case WallMaterial.aerated: return 400;
      case WallMaterial.expandedClay: return 400;
      case WallMaterial.timber: return 200;
      case WallMaterial.frame: return 150;
    }
  }

  double _partitionThickness(WallMaterial m) {
    switch (m) {
      case WallMaterial.brick: return 120;
      case WallMaterial.aerated: return 100;
      case WallMaterial.expandedClay: return 100;
      case WallMaterial.timber: return 100;
      case WallMaterial.frame: return 100;
    }
  }

  FoundationType _selectFoundation(HouseLayoutConfig config) {
    if ((config.wallMaterial == WallMaterial.brick || config.wallMaterial == WallMaterial.expandedClay) && config.floors >= 2) return FoundationType.strip;
    if (config.wallMaterial == WallMaterial.frame || config.wallMaterial == WallMaterial.timber) return FoundationType.pileWithGrillage;
    if (config.wallMaterial == WallMaterial.aerated && config.floors == 1) return FoundationType.slab;
    return FoundationType.strip;
  }

  double _roofSlope(RoofType type) {
    switch (type) {
      case RoofType.gable: return 30;
      case RoofType.hip: return 25;
      case RoofType.flat: return 3;
      case RoofType.mansard: return 60;
      case RoofType.shed: return 15;
      case RoofType.gambrel: return 45;
      case RoofType.combined: return 30;
      case RoofType.butterfly: return 20;
    }
  }

  RoofingMaterial _selectRoofing(RoofType type) {
    switch (type) {
      case RoofType.flat: return RoofingMaterial.membrane;
      case RoofType.mansard: return RoofingMaterial.softBitumen;
      case RoofType.gable: case RoofType.hip: case RoofType.combined: return RoofingMaterial.metalTile;
      case RoofType.shed: case RoofType.gambrel: case RoofType.butterfly: return RoofingMaterial.profileSheet;
    }
  }
}
