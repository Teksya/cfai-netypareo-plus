import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/netypareo_client.dart';
import 'models.dart';
import 'parsers.dart';

enum AuthStatus { loading, loggedOut, loggedIn }

/// État global de l'application : session, profil, emploi du temps en cache.
class AppState extends ChangeNotifier {
  AppState._(this._client, this._prefs);

  static const _secure = FlutterSecureStorage();
  static const _kUser = 'username';
  static const _kPassword = 'password';
  static const _kIcal = 'icalUrl';
  static const _kProfile = 'profile';
  static const _kSeances = 'seances';
  static const _kLastSync = 'lastSync';

  final NetypareoClient _client;
  final SharedPreferences _prefs;

  AuthStatus status = AuthStatus.loading;
  Profile? profile;
  List<Seance> seances = const [];
  DateTime? lastSync;
  bool syncing = false;
  String? syncError;

  Timer? _keepAlive;

  static Future<AppState> create() async {
    final state = AppState._(await NetypareoClient.create(), await SharedPreferences.getInstance());
    state._client.onSessionExpired = state._relogin;
    unawaited(state._restore());
    return state;
  }

  Future<void> _restore() async {
    final user = await _secure.read(key: _kUser);
    final profileJson = _prefs.getString(_kProfile);
    if (user == null || profileJson == null) {
      status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }
    profile = Profile.fromJson(jsonDecode(profileJson) as Map<String, dynamic>);
    final cached = _prefs.getString(_kSeances);
    if (cached != null) {
      seances = (jsonDecode(cached) as List).map((e) => Seance.fromJson(e as Map<String, dynamic>)).toList();
    }
    final last = _prefs.getString(_kLastSync);
    lastSync = last == null ? null : DateTime.tryParse(last);
    status = AuthStatus.loggedIn;
    notifyListeners();
    _startKeepAlive();
    unawaited(sync());
  }

  // ---------------------------------------------------------------------------
  // Connexion

  /// Renvoie un défi 2FA si le site en demande un, sinon null (connexion réussie).
  Future<OtpChallenge?> login(String username, String password) async {
    final result = await _client.login(username, password);
    await _secure.write(key: _kUser, value: username);
    await _secure.write(key: _kPassword, value: password);
    return _afterLogin(result);
  }

  Future<OtpChallenge?> submitOtp(OtpChallenge challenge, String code) async =>
      _afterLogin(await _client.submitOtp(challenge, code));

  Future<OtpChallenge?> _afterLogin(LoginResult result) async {
    if (result is LoginNeedsOtp) return result.challenge;
    await _loadProfile();
    status = AuthStatus.loggedIn;
    notifyListeners();
    _startKeepAlive();
    unawaited(sync(force: true));
    return null;
  }

  Future<bool> _relogin() async {
    final user = await _secure.read(key: _kUser);
    final password = await _secure.read(key: _kPassword);
    if (user == null || password == null) return false;
    try {
      return await _client.login(user, password) is LoginSuccess;
    } on NetypareoException {
      return false;
    }
  }

  Future<void> logout() async {
    _keepAlive?.cancel();
    try {
      await _client.logout();
    } catch (_) {
      // Déconnexion locale même sans réseau.
    }
    await _secure.deleteAll();
    await _prefs.clear();
    profile = null;
    seances = const [];
    lastSync = null;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  void _startKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(minutes: 10), (_) => _client.keepAlive().ignore());
  }

  Future<void> _loadProfile() async {
    final accueil = parseAccueil(await _client.getHtml('/apprenant/accueil'));
    final code = accueil.codeApprenant;
    if (code == null) throw const NetypareoException('Impossible de lire ton profil apprenant.');
    final inscription = parseInscription(await _client.getHtml('/apprenant/assiduite/'));
    profile = Profile(
      displayName: accueil.name,
      period: accueil.period,
      codeApprenant: code,
      codeInscription: inscription.codeInscription,
      formation: inscription.formation,
    );
    await _prefs.setString(_kProfile, jsonEncode(profile!.toJson()));
  }

  // ---------------------------------------------------------------------------
  // Emploi du temps (flux iCal, sans session une fois l'URL connue)

  Future<void> sync({bool force = false}) async {
    if (syncing) return;
    if (!force && lastSync != null && DateTime.now().difference(lastSync!) < const Duration(minutes: 15)) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      var url = await _secure.read(key: _kIcal);
      if (url == null) {
        final modal = await _client.getHtml('/planning/modal-icalendar-ressource/7500/${profile!.codeApprenant}');
        url = parseIcalUrl(modal.outerHtml);
        if (url == null) throw const NetypareoException('Lien iCalendar introuvable.');
        await _secure.write(key: _kIcal, value: url);
      }
      final ics = await _client.getPublicText(url);
      seances = parseIcal(ics, codeApprenant: profile?.codeApprenant);
      lastSync = DateTime.now();
      await _prefs.setString(_kSeances, jsonEncode(seances.map((s) => s.toJson()).toList()));
      await _prefs.setString(_kLastSync, lastSync!.toIso8601String());
    } catch (e) {
      syncError = _message(e);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  List<Seance> seancesOn(DateTime day) =>
      seances.where((s) => s.start.year == day.year && s.start.month == day.month && s.start.day == day.day).toList();

  // ---------------------------------------------------------------------------
  // Données à la demande (session requise)

  Future<SeanceDetail> seanceDetail(int codeSeance) async =>
      parseSeanceDetail(await _client.getHtml('/planning/seance/$codeSeance/7500/${profile!.codeApprenant}'));

  Future<List<Absence>> absences() async => parseAbsences(await _client.getHtml('/apprenant/assiduite/'));

  Future<List<CahierEntry>> cahierDeTextes() async =>
      parseCahierDeTextes(await _client.getHtml('/pedagogie/apprenant/bilan/consultation-libre-cdt/'));

  Future<({File file, String mimeType})> downloadDocument(DocumentLink link) =>
      _client.downloadDocument(link.path, link.name);

  static String _message(Object e) {
    debugPrint('NetYParéo erreur : $e');
    if (e is NetypareoException) return e.message;
    return 'Connexion à NetYParéo impossible. Vérifie ton réseau.';
  }

  static String errorMessage(Object e) => _message(e);

  @override
  void dispose() {
    _keepAlive?.cancel();
    super.dispose();
  }
}
