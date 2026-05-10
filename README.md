# Конструктор Строений

Flutter-приложение для проектирования и расчёта индивидуальных
жилых строений (ИЖС) с автоматической генерацией комплекта
рабочих чертежей по ГОСТ Р 21.101-2020.

## Сборка

- **Web (production):** `./deploy.sh` — выкатывает в Yandex Object Storage + сбрасывает CDN. Адрес: https://konstruktor-stroenii.ru/
- **Windows installer (.exe):** автоматически собирается через GitHub Actions на каждый push в `main`. Артефакты — в [Actions](../../actions). Тегированные релизы (`v*`) выкладываются в [Releases](../../releases). Локальная сборка — см. [`BUILD_WINDOWS.md`](BUILD_WINDOWS.md).
- **Web (debug):** `flutter run -d chrome`.

## Структура

| Папка | Что в ней |
|-------|-----------|
| `lib/` | Dart-исходники приложения |
| `lib/services/pdf_*.dart` | генератор рабочих чертежей в PDF |
| `lib/services/building3d_*.dart` | 3D-аксонометрия (на Flutter Canvas, без WebGL) |
| `lib/widgets/building3d_view.dart` | on-screen 3D-вид |
| `packages/cc_engine/` | расчётный движок (СП-нагрузки, армирование, теплотехника) |
| `assets/fonts/` | DejaVu Sans (для кириллицы в PDF) |
| `test/` | unit + integration tests (136/136) |
| `windows/` | Flutter Windows runner |
| `installer/` | Inno Setup script для установщика |

См. также `HANDOFF.md`, `PROJECT_STATE.md`, `BUILD_WINDOWS.md`.
