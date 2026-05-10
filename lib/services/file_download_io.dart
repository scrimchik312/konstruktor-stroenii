// v68.11 §28: десктоп-реализация скачивания/предпросмотра файлов.
// Вызывается из `file_download.dart` через conditional import при
// наличии `dart.library.io` (Windows / macOS / Linux / Android / iOS,
// то есть всё, что НЕ web).
//
// Поведение:
//  * `downloadBytesImpl` — сохраняет байты в системную папку
//    «Documents/Конструктор Строений/» с указанным именем и
//    показывает её в проводнике, открыв сам файл по умолчанию.
//  * `previewBytesImpl` — пишет файл во временную папку с
//    предсказуемым именем и открывает системным просмотрщиком
//    (на Windows — `cmd /c start`, на macOS — `open`, на Linux —
//    `xdg-open`).
//
// Не использует `file_picker` — тот тянет тяжёлые нативные
// зависимости. Для базового кейса (PDF/DXF в Documents) этого
// достаточно. Если нужно выбрать произвольную папку, можно позже
// добавить `file_selector`.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

const String _appFolderName = 'Конструктор Строений';

Future<void> downloadBytesImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final docs = await getApplicationDocumentsDirectory();
  final outDir = Directory('${docs.path}${Platform.pathSeparator}$_appFolderName');
  if (!await outDir.exists()) {
    await outDir.create(recursive: true);
  }
  final outFile = File('${outDir.path}${Platform.pathSeparator}$filename');
  await outFile.writeAsBytes(bytes, flush: true);
  // Открываем файл системным просмотрщиком — пользователь сразу видит результат.
  await _openWithDefaultApp(outFile.path);
}

Future<void> previewBytesImpl({
  required Uint8List bytes,
  String mimeType = 'application/pdf',
}) async {
  final tempDir = await getTemporaryDirectory();
  final ext = _extensionFor(mimeType);
  final ts = DateTime.now().millisecondsSinceEpoch;
  final outFile = File('${tempDir.path}${Platform.pathSeparator}preview_$ts.$ext');
  await outFile.writeAsBytes(bytes, flush: true);
  await _openWithDefaultApp(outFile.path);
}

String _extensionFor(String mimeType) {
  switch (mimeType) {
    case 'application/pdf':
      return 'pdf';
    case 'image/png':
      return 'png';
    case 'image/jpeg':
      return 'jpg';
    case 'application/dxf':
    case 'image/vnd.dxf':
      return 'dxf';
    case 'application/zip':
      return 'zip';
    case 'text/plain':
      return 'txt';
    default:
      return 'bin';
  }
}

Future<void> _openWithDefaultApp(String path) async {
  if (Platform.isWindows) {
    // `cmd /c start "" "<path>"` — пустой первый аргумент критичен,
    // иначе start считает его заголовком окна.
    await Process.start(
      'cmd',
      ['/c', 'start', '', path],
      runInShell: false,
      mode: ProcessStartMode.detached,
    );
  } else if (Platform.isMacOS) {
    await Process.start('open', [path], mode: ProcessStartMode.detached);
  } else if (Platform.isLinux) {
    await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
  }
  // На Android/iOS без url_launcher системный просмотрщик не открыть.
  // Файл сохранён, путь возвращён вызывающему через downloadBytesImpl.
}
