import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:html/dom.dart' show Document;
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';

import 'cp1252.dart';

const String kNetypareoHost = 'https://netypareo.citedesentreprises.org';
const String kNetypareoBase = '$kNetypareoHost/netypareo/index.php';

class NetypareoException implements Exception {
  const NetypareoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Identifiants refusés, ou session impossible à rétablir.
class AuthException extends NetypareoException {
  const AuthException(super.message);
}

/// Formulaire de double authentification renvoyé après le login.
class OtpChallenge {
  const OtpChallenge({required this.action, required this.fields, required this.codeField, required this.message});
  final String action;
  final Map<String, String> fields;
  final String codeField;
  final String message;
}

sealed class LoginResult {
  const LoginResult();
}

class LoginSuccess extends LoginResult {
  const LoginSuccess();
}

class LoginNeedsOtp extends LoginResult {
  const LoginNeedsOtp(this.challenge);
  final OtpChallenge challenge;
}

/// Accès HTTP à NetYParéo : cookies de session, décodage, reconnexion automatique.
///
/// Voir docs/netypareo-api.md pour la carte des endpoints.
class NetypareoClient {
  NetypareoClient._(this._dio, this._jar);

  final Dio _dio;
  final PersistCookieJar _jar;

  /// Appelé quand la session a expiré : doit se reconnecter et renvoyer true si c'est réussi.
  Future<bool> Function()? onSessionExpired;

  static Future<NetypareoClient> create() async {
    final dir = await getApplicationSupportDirectory();
    final jar = PersistCookieJar(storage: FileStorage('${dir.path}/cookies/'));

    // Le serveur du CFA n'envoie pas son certificat intermédiaire (Sectigo DV R36) :
    // les navigateurs le retrouvent seuls, pas Android. On le fournit pour compléter la chaîne,
    // la vérification TLS reste complète jusqu'à la racine du système.
    final intermediate = await rootBundle.load('assets/certs/sectigo_dv_r36.pem');
    final context = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(intermediate.buffer.asUint8List());

    final dio = Dio(BaseOptions(
      baseUrl: kNetypareoBase,
      responseType: ResponseType.bytes,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => status != null && status < 500,
      headers: {'User-Agent': 'NetYPareoPlus/0.1 (Android; Flutter)'},
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => HttpClient(context: context));
    dio.interceptors.add(CookieManager(jar));
    return NetypareoClient._(dio, jar);
  }

  // ---------------------------------------------------------------------------
  // Authentification

  Future<LoginResult> login(String username, String password) async {
    await _jar.deleteAll();
    final loginPage = await _rawGet('/');
    final form = loginPage.document.querySelector('form[action*="/authentication/"]');
    final token = form?.querySelector('input[name="token_csrf"]')?.attributes['value'];
    if (form == null || token == null) {
      throw const NetypareoException('Page de connexion NetYParéo introuvable.');
    }

    final response = await _dio.post<List<int>>(
      '/authentication/',
      data: {
        'login': username,
        'password': password,
        'screenWidth': '412',
        'screenHeight': '915',
        'token_csrf': token,
        'btnSeConnecter': '',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
      ),
    );
    return _followLogin(response);
  }

  Future<LoginResult> submitOtp(OtpChallenge challenge, String code) async {
    final url = challenge.action.startsWith('http') ? challenge.action : '$kNetypareoHost${challenge.action}';
    final response = await _dio.post<List<int>>(
      url,
      data: {...challenge.fields, challenge.codeField: code},
      options: Options(contentType: Headers.formUrlEncodedContentType, followRedirects: false),
    );
    return _followLogin(response);
  }

  /// Après le POST : un échec redirige vers /login/{codeErreur}/, un succès vers l'accueil
  /// (ou vers l'écran de double authentification).
  Future<LoginResult> _followLogin(Response<List<int>> response) async {
    final location = response.headers.value(HttpHeaders.locationHeader) ?? '';
    if (location.contains('/login/')) {
      final page = await _rawGet(location.replaceFirst('/netypareo/index.php', ''));
      final error = page.document
          .querySelector('.alert, .error, [class*=erreur], [class*=error]')
          ?.text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      throw AuthException(error == null || error.isEmpty ? 'Identifiant ou mot de passe incorrect.' : error);
    }
    if (location.isNotEmpty) {
      final next = await _rawGet(location.replaceFirst('/netypareo/index.php', ''));
      final otp = _parseOtp(next.document);
      if (otp != null) return LoginNeedsOtp(otp);
    } else {
      final otp = _parseOtp(html_parser.parse(_decode(response)));
      if (otp != null) return LoginNeedsOtp(otp);
    }
    final home = await _rawGet('/apprenant/accueil');
    final otp = _parseOtp(home.document);
    if (otp != null) return LoginNeedsOtp(otp);
    if (home.status != 200 || home.document.querySelector('.user-info-label') == null) {
      throw const AuthException('NetYParéo a refusé la connexion.');
    }
    return const LoginSuccess();
  }

  OtpChallenge? _parseOtp(Document doc) {
    final form = doc.querySelector('#twofa-form');
    if (form == null) return null;
    final fields = <String, String>{};
    String? codeField;
    for (final input in form.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name == null) continue;
      if (input.id == 'js-twofa-code') {
        codeField = name;
      } else if (!input.classes.contains('js-twofa-digit')) {
        fields[name] = input.attributes['value'] ?? '';
      }
    }
    final message = doc.querySelector('#js-twofa-region')?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return OtpChallenge(
      action: form.attributes['action'] ?? '/netypareo/index.php/authentication/',
      fields: fields,
      codeField: codeField ?? 'code',
      message: message,
    );
  }

  Future<void> logout() async {
    try {
      await _dio.get<List<int>>('/logout/');
    } finally {
      await _jar.deleteAll();
    }
  }

  Future<void> keepAlive() => _dio.get<List<int>>('/rester-connecter/');

  // ---------------------------------------------------------------------------
  // Requêtes avec reconnexion automatique

  /// GET d'une page HTML protégée. Se reconnecte une fois si la session a expiré.
  Future<Document> getHtml(String path) async => (await _authed(() => _rawGet(path))).document;

  Future<Document> postHtml(String path, Map<String, dynamic> data) async =>
      (await _authed(() => _rawPost(path, data))).document;

  /// Texte brut d'une page protégée, pour le cache (voir `PageCache`).
  Future<String> getText(String path) async => (await _authed(() => _rawGet(path))).text;

  Future<String> postText(String path, Map<String, dynamic> data) async =>
      (await _authed(() => _rawPost(path, data))).text;

  Future<dynamic> getJson(String path) async {
    final page = await _authed(() => _rawGet(path, ajax: true));
    return jsonDecode(page.text);
  }

  /// Télécharge une pièce jointe (`/netypareo/index.php/document/telecharger/{token}/`) dans le cache.
  /// Si le serveur renvoie une page HTML au lieu du fichier, la session a expiré : on se reconnecte une fois.
  Future<({File file, String mimeType})> downloadDocument(String path, String fileName) async {
    final url = path.startsWith('http') ? path : '$kNetypareoHost$path';
    Future<Response<List<int>>> fetch() => _dio.get<List<int>>(url);

    var response = await fetch();
    if (_isHtml(response)) {
      if (await _sessionAlive()) throw const NetypareoException('Pièce jointe introuvable sur NetYParéo.');
      final relogged = await onSessionExpired?.call() ?? false;
      if (!relogged) throw const AuthException('Session expirée. Reconnecte-toi.');
      response = await fetch();
      if (_isHtml(response)) throw const NetypareoException('Pièce jointe introuvable sur NetYParéo.');
    }

    final dir = Directory('${(await getTemporaryDirectory()).path}/pieces-jointes');
    await dir.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final file = File('${dir.path}/${safeName.isEmpty ? 'document' : safeName}');
    await file.writeAsBytes(response.data ?? const []);
    final type = (response.headers.value(HttpHeaders.contentTypeHeader) ?? '').split(';').first.trim();
    final generic = type.isEmpty || type == 'application/octet-stream' || type == 'application/force-download';
    return (file: file, mimeType: generic ? mimeFromName(safeName) : type);
  }

  /// Type MIME d'après l'extension, pour que Android propose la bonne application.
  static String mimeFromName(String name) => switch (name.split('.').last.toLowerCase()) {
        'pdf' => 'application/pdf',
        'odt' => 'application/vnd.oasis.opendocument.text',
        'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
        'odp' => 'application/vnd.oasis.opendocument.presentation',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'txt' || 'sh' || 'conf' || 'log' => 'text/plain',
        'csv' => 'text/csv',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'zip' => 'application/zip',
        _ => 'application/octet-stream',
      };

  static bool _isHtml(Response<List<int>> response) =>
      (response.headers.value(HttpHeaders.contentTypeHeader) ?? '').contains('text/html');

  /// Texte brut sans session (flux iCal).
  Future<String> getPublicText(String url) async {
    final response = await _dio.get<List<int>>(url);
    return _decode(response);
  }

  /// Sans session, NetYParéo répond 404 (ou la page de login) : on vérifie alors la session,
  /// on se reconnecte si besoin, puis on rejoue la requête une fois.
  Future<_Page> _authed(Future<_Page> Function() request) async {
    var page = await request();
    if (page.status != 404 && !_isLoginPage(page.text)) return page;
    if (await _sessionAlive()) {
      throw const NetypareoException('Cette page n\'existe pas (ou plus) sur NetYParéo.');
    }
    final relogged = await onSessionExpired?.call() ?? false;
    if (!relogged) throw const AuthException('Session expirée. Reconnecte-toi.');
    page = await request();
    if (page.status == 404) throw const NetypareoException('Cette page n\'existe pas (ou plus) sur NetYParéo.');
    if (_isLoginPage(page.text)) throw const AuthException('Session expirée. Reconnecte-toi.');
    return page;
  }

  Future<bool> _sessionAlive() async {
    final page = await _rawGet('/rester-connecter/', ajax: true);
    return page.status == 200 && page.text.contains('success');
  }

  Future<_Page> _rawGet(String path, {bool ajax = false}) async {
    final response = await _dio.get<List<int>>(
      path,
      options: Options(headers: ajax ? {'X-Requested-With': 'XMLHttpRequest'} : null),
    );
    return _Page(_decode(response), response.statusCode ?? 0);
  }

  Future<_Page> _rawPost(String path, Map<String, dynamic> data) async {
    final response = await _dio.post<List<int>>(
      path,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'X-Requested-With': 'XMLHttpRequest'},
      ),
    );
    return _Page(_decode(response), response.statusCode ?? 0);
  }

  static bool _isLoginPage(String html) => html.contains('/netypareo/index.php/authentication/');

  static String _decode(Response<List<int>> response) {
    final bytes = response.data ?? const <int>[];
    final type = response.headers.value(HttpHeaders.contentTypeHeader)?.toLowerCase() ?? '';
    if (type.contains('1252') || type.contains('iso-8859')) return decodeCp1252(bytes);
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class _Page {
  _Page(this.text, this.status);
  final String text;
  final int status;
  late final Document document = html_parser.parse(text);
}
