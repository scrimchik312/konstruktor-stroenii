import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> downloadBytesImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  // Используем blob-URL вместо data:URL — у браузеров есть лимит
  // ~2 МБ на data:URL, а наши PDF могут быть больше.
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(const Duration(seconds: 30), () {
    web.URL.revokeObjectURL(url);
  });
}

/// Открывает байты в новой вкладке. Чтобы попап-блокировщики не закрывали
/// окно после `await`-а на генерацию PDF, мы синхронно открываем пустую
/// вкладку перед началом генерации (вызов из `previewBytes` уже после
/// генерации, поэтому здесь — fallback: если open() возвращает null
/// (заблокировано), используем «Save As» через скачивание).
Future<void> previewBytesImpl({
  required Uint8List bytes,
  required String mimeType,
}) async {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  // Сначала пробуем открыть PDF в новой вкладке.
  final win = web.window.open(url, '_blank');
  // Если попап заблокирован — открываем встроенный оверлей с iframe.
  // ignore: unnecessary_null_comparison
  final blocked = win == null;
  if (blocked) {
    // Попап заблокирован — fallback: внедряем iframe в текущую страницу.
    final overlay = web.HTMLDivElement()
      ..id = '__pdf_preview_overlay__'
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.background = 'rgba(0,0,0,0.85)'
      ..style.zIndex = '999999'
      ..style.display = 'flex'
      ..style.flexDirection = 'column';
    final closeBar = web.HTMLDivElement()
      ..style.height = '44px'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'flex-end'
      ..style.padding = '6px 18px'
      ..style.background = '#333';
    final closeBtn = web.HTMLButtonElement()
      ..textContent = '✕  Закрыть предпросмотр'
      ..style.background = '#fff'
      ..style.color = '#000'
      ..style.border = 'none'
      ..style.padding = '6px 14px'
      ..style.borderRadius = '4px'
      ..style.cursor = 'pointer'
      ..style.fontSize = '14px';
    closeBtn.onClick.listen((_) {
      overlay.remove();
      web.URL.revokeObjectURL(url);
    });
    closeBar.append(closeBtn);

    final iframe = web.HTMLIFrameElement()
      ..src = url
      ..style.flex = '1'
      ..style.border = 'none'
      ..style.background = '#fff';

    overlay
      ..append(closeBar)
      ..append(iframe);
    web.document.body?.append(overlay);
    return;
  }

  // URL живёт до закрытия вкладки; через минуту страховочно отзываем.
  Future<void>.delayed(const Duration(minutes: 5), () {
    web.URL.revokeObjectURL(url);
  });
}
