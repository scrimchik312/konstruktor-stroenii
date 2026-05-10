# Сборка Windows-установщика «Конструктор Строений»

Пошаговая инструкция: на чистой Windows 10/11 собрать
самораспаковывающийся `.exe` установщик. По итогу пользователь
получает программу, которая запускается из «Пуск» / ярлыка на
рабочем столе и работает офлайн.

## 1. Что нужно установить (один раз)

| Инструмент | Зачем | Где скачать |
|-----------|-------|-------------|
| **Flutter SDK 3.24+** (channel `stable`) | сборка Dart→native | https://docs.flutter.dev/get-started/install/windows |
| **Visual Studio 2022 Community** + workload **«Разработка классических приложений на C++»** (Desktop development with C++) | компилятор MSVC, Windows SDK | https://visualstudio.microsoft.com/ru/downloads/ |
| **Git** (опционально, для `flutter doctor`) | — | https://git-scm.com/download/win |
| **Inno Setup 6** | сборка установщика | https://jrsoftware.org/isdl.php |

После установки Visual Studio в установщике обязательно отметьте:
- ✅ Разработка классических приложений на C++ (Desktop dev with C++)
- ✅ MSVC v143 — VS 2022 C++ x64/x86 build tools
- ✅ Windows 10/11 SDK (10.0.19041 или новее)

После установки Flutter добавьте в `PATH` папку `C:\src\flutter\bin`
(или куда распаковали SDK), перезапустите PowerShell и проверьте:
```powershell
flutter doctor -v
```
Все пункты должны быть зелёные. Если в разделе «Visual Studio»
жалуется на компоненты — открыть Visual Studio Installer и
поставить недостающее.

## 2. Распакуйте архив проекта

Архив называется `konstruktor_stroenii_v68_11.tar.gz` (или `.zip`,
если присылали zip-вариант). Распакуйте в любую папку без
кириллицы и пробелов в пути, например `C:\dev\konstruktor`.
Проверьте, что внутри есть файл `pubspec.yaml`.

```powershell
cd C:\dev\konstruktor\construction_calculator
```

## 3. Подтяните зависимости

```powershell
flutter pub get
```

Должно завершиться без ошибок. На этом шаге Flutter скачает все
pub-пакеты (около 200 МБ в `%LOCALAPPDATA%\Pub\Cache`).

## 4. Соберите Windows-приложение

```powershell
flutter build windows --release
```

Сборка занимает 2–5 минут. Готовый бинарник появится в:
```
build\windows\x64\runner\Release\
├── konstruktor_stroenii.exe   ← основной .exe (~30 МБ)
├── flutter_windows.dll
├── *.dll                       ← плагины (path_provider и т.д.)
└── data\                       ← ассеты, шрифты, dart-снапшот
```

Проверьте, что приложение запускается двойным кликом по
`konstruktor_stroenii.exe`. Должно открыться окно «Конструктор
Строений» 1280×720.

⚠️ **Важно:** перемещать или копировать вы можете **только всю
папку Release целиком** — без `flutter_windows.dll` и `data/`
приложение не запустится. Именно поэтому дальше мы делаем
установщик.

## 5. Соберите установщик через Inno Setup

В архиве уже лежит готовый скрипт `installer/konstruktor_stroenii.iss`.

**Способ А — двойным кликом:**
1. Откройте `installer\konstruktor_stroenii.iss` в Inno Setup
   Compiler.
2. Нажмите **Build → Compile** (или клавишу `F9`).
3. После «Successful compile» нажмите **Run → Run** (`F9` второй
   раз) — это запустит установщик прямо из IDE для проверки.

**Способ Б — из командной строки:**
```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\konstruktor_stroenii.iss
```

Готовый файл появится в:
```
installer\Output\KonstruktorStroenii-Setup-1.0.0.exe
```
Размер — около 30–40 МБ (архив запакован LZMA2). Это и есть
установщик, который можно отдавать конечным пользователям.

## 6. Что делает установщик

При запуске `KonstruktorStroenii-Setup-1.0.0.exe`:
- спрашивает язык (русский / английский);
- предлагает целевую папку (по умолчанию
  `C:\Program Files\Конструктор Строений\`);
- ставит ярлык в меню «Пуск» и опционально на рабочий стол;
- регистрирует деинсталлятор (Панель управления → Удаление программ).

Файлы, генерируемые программой (PDF/DXF), сохраняются в
`Documents\Конструктор Строений\` — пользователю не нужны права
администратора, чтобы скачивать чертежи.

## 7. Обновление версии

Изменить версию надо в **трёх местах** (Inno Setup сам берёт её
из `.iss`, так что укажите вручную):

1. `pubspec.yaml`: `version: 1.0.1+2`
2. `installer/konstruktor_stroenii.iss`: `#define MyAppVersion "1.0.1"`
3. (по желанию) `windows/runner/Runner.rc` — там
   `VERSION_AS_STRING` подставится автоматически из `pubspec.yaml`
   через сборку Flutter.

После этого повторить шаги 4–5.

## 8. Известные ограничения

- **Подпись кода (code signing).** Без подписи Windows SmartScreen
  при первом запуске покажет «Защитник Windows предотвратил запуск
  неизвестного приложения». Чтобы убрать предупреждение, нужен
  Authenticode-сертификат от GlobalSign / Sectigo / DigiCert
  (~5–15 тыс. ₽/год). Подписывать командой `signtool`. На этом
  шаге это **не делается**.
- **Авто-обновление.** Установщик не реализует автообновление; для
  новой версии запустите новый `Setup-X.Y.Z.exe` поверх старой.
- **macOS / Linux.** Та же сборка работает командами
  `flutter build macos --release` и `flutter build linux --release`,
  но установщик надо собирать другими инструментами (DMG / .deb).

## 9. Если что-то пошло не так

| Симптом | Решение |
|---------|---------|
| `flutter doctor` ругается на «Visual Studio – missing components» | Открыть Visual Studio Installer → «Изменить» → выбрать workload «Разработка классических приложений на C++». |
| `flutter build windows` падает с `MSBuild error MSB8020` | Не установлен Windows 10/11 SDK. Установить через VS Installer. |
| `ISCC.exe` ругается «Source file does not exist» | Не выполнили `flutter build windows --release` или путь содержит кириллицу. Перепроверьте `installer/konstruktor_stroenii.iss` — `BuildRoot` должен указывать на существующую `build\windows\x64\runner\Release`. |
| Установщик собрался, но при запуске «приложение не запускается» | Убедитесь, что в Release-папке есть `flutter_windows.dll` и подпапка `data\`. Если нет — повторите сборку с очисткой: `flutter clean && flutter pub get && flutter build windows --release`. |
| В программе нет кириллицы / квадратики вместо букв | Проверьте, что `assets/fonts/DejaVuSans*.ttf` попали в установку. Они есть в `pubspec.yaml` → `flutter.assets`. |

Готово. Установщик `KonstruktorStroenii-Setup-1.0.0.exe` —
самодостаточный, можно отправлять заказчику.
