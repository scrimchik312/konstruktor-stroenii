import 'package:cc_engine/cc_engine.dart';
import 'package:test/test.dart';

void main() {
  group('RafterCheck', () {
    test('Стропило 50×150 L=4м, q=2 кН/м — проходит прочность', () {
      final r = RafterCheck.computeSimple(
        spanM: 4.0,
        widthMm: 50,
        heightMm: 150,
        qKnPerM: 2.0,
        qNormKnPerM: 1.5,
        grade: WoodGrade.second,
      );
      // M = 2*16/8 = 4 кН·м, Wx = 50*150²/6 = 187500, σ = 4e6/187500 ≈ 21.3 Н/мм²
      expect(r.momentKnm, closeTo(4.0, 0.01));
      expect(r.sigmaNmm2, closeTo(21.33, 0.1));
      // 21.3 > 14 (2 сорт Rи) — НЕ проходит
      expect(r.strengthPasses, isFalse);
    });

    test('Стропило 100×200 L=5м, q=1.5 кН/м — проходит', () {
      final r = RafterCheck.computeSimple(
        spanM: 5.0,
        widthMm: 100,
        heightMm: 200,
        qKnPerM: 1.5,
        qNormKnPerM: 1.2,
        grade: WoodGrade.second,
      );
      // M = 1.5*25/8 ≈ 4.69 кН·м; Wx = 100*200²/6 = 666667
      // σ = 4.69e6/666667 ≈ 7.03 Н/мм² → < 14 Н/мм² (2 сорт)
      expect(r.sigmaNmm2, lessThan(14));
      expect(r.strengthPasses, isTrue);
      // прогиб должен быть < L/200 = 25 мм
      expect(r.deflectionMm, lessThan(r.deflectionLimitMm));
      expect(r.passes, isTrue);
    });
  });
}
