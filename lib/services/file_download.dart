import 'dart:convert';
import 'dart:typed_data';

// v68.11 §28: для десктоп-сборок (Windows/macOS/Linux) включаем
// io-реализацию, которая пишет файл в Documents и открывает его
// системным просмотрщиком. На вебе — `package:web` (data:-URL).
// `dart.library.io` истинно на всех non-web сборках.
import 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';

/// Скачивание файла на устройство пользователя. На Web — через
/// `data:`-URL и эмулированный клик по `<a download>`. На остальных
/// платформах сейчас бросает `UnsupportedError` (приложение целевое
/// для веба; для нативных платформ можно прикрутить file_saver).
class FileDownload {
  FileDownload._();

  static Future<void> downloadBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) =>
      downloadBytesImpl(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );

  static Future<void> downloadText({
    required String content,
    required String filename,
    required String mimeType,
  }) =>
      downloadBytes(
        bytes: Uint8List.fromList(utf8.encode(content)),
        filename: filename,
        mimeType: mimeType,
      );

  /// Открывает байты в новой вкладке браузера для предпросмотра
  /// (PDF — встроенным вьюером, изображения и т. п.). На non-web —
  /// бросает [UnsupportedError].
  static Future<void> previewBytes({
    required Uint8List bytes,
    String mimeType = 'application/pdf',
  }) =>
      previewBytesImpl(bytes: bytes, mimeType: mimeType);
}
