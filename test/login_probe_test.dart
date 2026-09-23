// Sonde manuelle du flow de login avec de FAUX identifiants : `flutter test test/login_probe_test.dart`.
// Attendu : AuthException "Identifiant ou mot de passe incorrect", pas une erreur réseau.
// ignore_for_file: avoid_print
@Tags(['network'])
library;

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:netypareo_plus/core/cp1252.dart';
import 'package:netypareo_plus/core/netypareo_client.dart';

void main() {
  test('login avec faux identifiants', () async {
    final dio = Dio(BaseOptions(
      baseUrl: kNetypareoBase,
      responseType: ResponseType.bytes,
      validateStatus: (s) => s != null && s < 500,
    ));
    final context = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(File('assets/certs/sectigo_dv_r36.pem').readAsBytesSync());
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => HttpClient(context: context));
    dio.interceptors.add(CookieManager(CookieJar()));
    try {
      final r1 = await dio.get<List<int>>('/');
      final page = decodeCp1252(r1.data!);
      print('GET / -> ${r1.statusCode} ${r1.realUri} ${r1.headers['content-type']} len=${page.length}');
      final doc = html_parser.parse(page);
      final token = doc.querySelector('input[name="token_csrf"]')?.attributes['value'];
      print('token=$token forms=${doc.querySelectorAll('form').map((f) => f.attributes['action']).toList()}');
      final r2 = await dio.post<List<int>>(
        '/authentication/',
        data: {'login': 'faux_compte_test', 'password': 'faux', 'screenWidth': '412', 'screenHeight': '915', 'token_csrf': token, 'btnSeConnecter': ''},
        options: Options(contentType: Headers.formUrlEncodedContentType, followRedirects: false),
      );
      print('POST -> ${r2.statusCode} location=${r2.headers['location']}');
      final r3 = await dio.get<List<int>>('/apprenant/accueil');
      final t3 = decodeCp1252(r3.data!);
      print('GET accueil -> ${r3.statusCode} ${r3.realUri} loginPage=${t3.contains('/authentication/')}');
      final r4 = await dio.get<List<int>>('/rester-connecter/', options: Options(headers: {'X-Requested-With': 'XMLHttpRequest'}));
      print('rester-connecter -> ${r4.statusCode} ${r4.headers['content-type']} ${decodeCp1252(r4.data!).substring(0, 80)}');
      final r5 = await dio.get<List<int>>('/login/2/');
      final t5 = html_parser.parse(decodeCp1252(r5.data!));
      print('login/2 -> ${r5.statusCode} erreur="${t5.querySelector('.alert, .error, [class*=erreur], [class*=error]')?.text.replaceAll(RegExp(r'\s+'), ' ').trim()}"');
    } on DioException catch (e) {
      print('DioException ${e.type} ${e.message} ${e.error}');
      rethrow;
    }
  });
}
