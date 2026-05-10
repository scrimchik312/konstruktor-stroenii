import 'package:cc_engine/cc_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ThermalCalculator', () {
    test('Москва: стена 400 мм газобетон D500 проходит по СП 50', () {
      final result = ThermalCalculator.compute(
        climate: ClimateZones.moscow,
        envelope: BuildingEnvelope.wall,
        layers: const [
          EnvelopeLayer(name: 'Газобетон D500', thicknessMm: 400, lambda: 0.14),
          EnvelopeLayer(name: 'Минвата', thicknessMm: 100, lambda: 0.042),
        ],
      );
      // Москва: tв=20, tот=-2.2, zот=205 → ГСОП = 22.2*205 = 4551
      expect(result.gsop, closeTo(4551.0, 1));
      // R_req стены = 0.00035*4551 + 1.4 ≈ 2.99
      expect(result.rReq, closeTo(2.99, 0.05));
      // R_actual = 1/8.7 + 0.4/0.14 + 0.1/0.042 + 1/23
      //         ≈ 0.115 + 2.857 + 2.381 + 0.043 ≈ 5.40
      expect(result.rActual, greaterThan(result.rReq));
      expect(result.passes, isTrue);
    });

    test('Москва: тонкая стена 150 мм бетона не проходит', () {
      final result = ThermalCalculator.compute(
        climate: ClimateZones.moscow,
        envelope: BuildingEnvelope.wall,
        layers: const [
          EnvelopeLayer(name: 'Бетон B25', thicknessMm: 150, lambda: 1.7),
        ],
      );
      expect(result.rActual, lessThan(result.rReq));
      expect(result.passes, isFalse);
    });

    test('Краснодар ГСОП меньше Новосибирска', () {
      expect(
        ClimateZones.krasnodar.gsop,
        lessThan(ClimateZones.novosibirsk.gsop),
      );
    });
  });
}
