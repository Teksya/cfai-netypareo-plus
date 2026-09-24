import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Pages NetYParéo déjà téléchargées, gardées sur le téléphone.
///
/// On garde le texte brut de la page, pas le résultat de la lecture : les parsers le relisent,
/// ce qui évite de sérialiser chaque modèle. Les fichiers restent dans le dossier privé de
/// l'application et sont effacés à la déconnexion (ils contiennent des données personnelles).
class PageCache {
  PageCache._(this._dir);

  final Directory _dir;

  /// Au-delà, les pages les moins récemment écrites sont supprimées (surtout des détails de séance).
  static const _maxFiles = 300;

  static Future<PageCache> open() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/pages');
    await dir.create(recursive: true);
    return PageCache._(dir);
  }

  File _file(String key) => File('${_dir.path}/${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.txt');

  Future<String?> read(String key) async {
    final file = _file(key);
    try {
      return await file.exists() ? await file.readAsString() : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String key, String text) async {
    await _file(key).writeAsString(text, flush: false);
    final files = _dir.listSync().whereType<File>().toList();
    if (files.length <= _maxFiles) return;
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final old in files.take(files.length - _maxFiles)) {
      old.deleteSync();
    }
  }

  Future<void> clear() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
    await _dir.create(recursive: true);
  }
}
