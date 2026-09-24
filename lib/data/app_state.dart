import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' show Document;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/netypareo_client.dart';
import '../core/page_cache.dart';
import 'background_sync.dart';
import 'calendar_mirror.dart';
import 'course_widget.dart';
import 'models.dart';
import 'notifications.dart';
import 'parsers.dart';

enum AuthStatus { loading, loggedOut, loggedIn }

/// État global de l'application : session, profil, emploi du temps en cache.
class AppState extends ChangeNotifier {
  AppState._(this._client, this._prefs, this._pages);

  static const _secure = kSecure;
  static const _kUser = 'username';
  static const _kPassword = 'password';
  static const _kIcal = kIcalKey;
  static const _kProfile = kProfileKey;

  final NetypareoClient _client;
  final SharedPreferences _prefs;
  final PageCache _pages;

  AuthStatus status = AuthStatus.loading;
  Profile? profile;
  List<Seance> seances = const [];
  DateTime? lastSync;
  bool syncing = false;
  String? syncError;

  /// Alertes de changement de cours (synchronisation en arrière-plan et notifications).
  bool get alertsEnabled => _prefs.getBool(kAlertsKey) ?? true;

  /// Copie du planning dans l'agenda du téléphone.
  bool get calendarEnabled => CalendarMirror.enabled(_prefs);

  /// Disposition du planning choisie (jour, 3 jours, semaine, liste).
  String? get planningLayout => _prefs.getString('planningLayout');

  Future<void> setPlanningLayout(String name) => _prefs.setString('planningLayout', name);

  Timer? _keepAlive;

  static Future<AppState> create() async {
    final state = AppState._(
      await NetypareoClient.create(),
      await SharedPreferences.getInstance(),
      await PageCache.open(),
    );
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
    seances = PlanningStore.read(_prefs) ?? const [];
    final last = _prefs.getString(kLastSyncKey);
    lastSync = last == null ? null : DateTime.tryParse(last);
    status = AuthStatus.loggedIn;
    notifyListeners();
    _startKeepAlive();
    unawaited(_scheduleAlerts());
    unawaited(CourseWidget.update(seances));
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
    unawaited(_scheduleAlerts());
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
    await BackgroundSync.cancel();
    await CalendarMirror.disable(_prefs);
    try {
      await _client.logout();
    } catch (_) {
      // Déconnexion locale même sans réseau.
    }
    await _secure.deleteAll();
    await _pages.clear();
    await _prefs.clear();
    await CourseWidget.update(const []);
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

  /// Programme la tâche de fond. L'autorisation de notifier n'est demandée qu'une fois :
  /// si elle est refusée, l'interrupteur de l'onglet "Plus" permet de la redemander.
  Future<void> _scheduleAlerts() async {
    try {
      if (!alertsEnabled) return BackgroundSync.cancel();
      if (!(_prefs.getBool('alertsAsked') ?? false)) {
        await _prefs.setBool('alertsAsked', true);
        await PlanningNotifications.requestPermission();
      }
      await BackgroundSync.schedule();
    } catch (e) {
      debugPrint('Alertes indisponibles : $e');
    }
  }

  /// Active ou coupe les alertes. Renvoie false si Android refuse les notifications.
  Future<bool> setAlerts(bool enabled) async {
    await _prefs.setBool(kAlertsKey, enabled);
    notifyListeners();
    if (!enabled) {
      await BackgroundSync.cancel();
      return true;
    }
    final allowed = await PlanningNotifications.requestPermission();
    await BackgroundSync.schedule();
    return allowed;
  }

  /// Active ou coupe la copie dans l'agenda. Renvoie false si Android refuse l'accès à l'agenda.
  Future<bool> setCalendar(bool enabled) async {
    try {
      if (!enabled) {
        await CalendarMirror.disable(_prefs);
        return true;
      }
      return await CalendarMirror.enable(_prefs, seances);
    } finally {
      notifyListeners();
    }
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
    if (!force && lastSync != null && DateTime.now().difference(lastSync!) < const Duration(minutes: 1)) return;
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
      final fresh = parseIcal(ics, codeApprenant: profile?.codeApprenant);
      final changes = await PlanningStore.save(_prefs, fresh);
      seances = fresh;
      lastSync = DateTime.now();
      if (alertsEnabled) await PlanningNotifications.showChanges(changes);
      unawaited(CalendarMirror.sync(_prefs, fresh).catchError((Object e) => debugPrint('Agenda : $e')));
      unawaited(CourseWidget.update(fresh));
    } catch (e) {
      syncError = _message(e);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Relit le planning enregistré, qui a pu être mis à jour par la tâche de fond.
  Future<void> reloadCache() async {
    await _prefs.reload();
    seances = PlanningStore.read(_prefs) ?? seances;
    final last = _prefs.getString(kLastSyncKey);
    lastSync = last == null ? lastSync : DateTime.tryParse(last);
    notifyListeners();
  }

  List<Seance> seancesOn(DateTime day) =>
      seances.where((s) => s.start.year == day.year && s.start.month == day.month && s.start.day == day.day).toList();

  // ---------------------------------------------------------------------------
  // Données à la demande (session requise)

  /// Version enregistrée d'abord (affichage immédiat, même hors ligne), puis version à jour
  /// seulement si la page a changé.
  /// Si le réseau échoue après la version enregistrée, le flux se termine par l'erreur :
  /// l'écran garde les données et signale qu'elles ne sont peut-être plus à jour.
  Stream<T> _cached<T>(String key, Future<String> Function() fetch, T Function(String text) parse) async* {
    final saved = await _pages.read(key);
    var shown = false;
    if (saved != null) {
      try {
        yield parse(saved);
        shown = true;
      } catch (e) {
        debugPrint('Cache illisible ($key) : $e');
      }
    }
    final fresh = await fetch();
    // Page identique à celle affichée : rien à redessiner.
    if (shown && fresh == saved) return;
    final value = parse(fresh);
    await _pages.write(key, fresh);
    yield value;
  }

  static T Function(String) _html<T>(T Function(Document doc) parse) => (text) => parse(html_parser.parse(text));

  Stream<SeanceDetail> seanceDetail(int codeSeance) => _cached(
        'seance-$codeSeance',
        () => _client.getText('/planning/seance/$codeSeance/7500/${profile!.codeApprenant}'),
        _html((d) => parseSeanceDetail(d)),
      );

  final _prefetched = <int>{};

  /// Télécharge en arrière-plan le détail des cours d'un jour (une fois par ouverture de
  /// l'application) : leur fiche s'ouvre ensuite directement complète.
  Future<void> prefetchSeanceDetails(DateTime day) async {
    if (profile == null) return;
    for (final s in seancesOn(day)) {
      final code = s.codeSeance;
      if (code == null || !_prefetched.add(code)) continue;
      try {
        await seanceDetail(code).drain<void>();
      } catch (e) {
        _prefetched.remove(code);
        return;
      }
    }
  }

  Stream<List<Absence>> absences() =>
      _cached('absences', () => _client.getText('/apprenant/assiduite/'), _html((d) => parseAbsences(d)));

  Stream<List<CahierEntry>> cahierDeTextes() => _cached(
        'cahier',
        () => _client.getText('/pedagogie/apprenant/bilan/consultation-libre-cdt/'),
        _html((d) => parseCahierDeTextes(d)),
      );

  Stream<List<TravailAFaire>> travailAFaire() =>
      _cached('travail', () => _client.getText('/travail-a-faire/'), _html((d) => parseTravailAFaire(d)));

  /// Écrit sur NetYParéo : le travail passe en "fait" (annulable).
  Future<void> declarerFait(TravailAFaire taf) => _client.postText('/travail-a-faire/declarer-fait/', {
        'codeNetTravailAFaire': taf.code,
        'codeApprenant': profile!.codeApprenant,
      });

  Future<void> annulerFait(TravailAFaire taf) => _client.postText('/travail-a-faire/supprimer-travail/', {
        'codeNetTravailFaitPar': taf.codeTravailFait,
      });

  /// Contenu d'un dossier de l'espace Documents ; [folder] null pour la racine.
  /// La racine demande d'abord la page de l'explorateur pour ses paramètres signés.
  Stream<List<DocEntry>> documents([DocEntry? folder]) => _cached(
        'docs-${folder?.path ?? 'racine'}',
        () async {
          final home = parseDocumentsHome(await _client.getText('/apprenant/documents/'));
          if (home == null) throw const NetypareoException('Espace Documents illisible.');
          return _client.postText('/document/liste/', {
            'explorerId': home.explorerId,
            'fsParams': folder?.fsParams ?? home.fsParams,
            'showFileMenu': 1,
            'path': folder?.path ?? base64.encode(utf8.encode('[null,null]')),
          });
        },
        _html((d) => parseDocumentList(d)),
      );

  /// Calendrier de formation : jours au centre, en entreprise ou indisponibles, sur l'année.
  Stream<Alternance> alternance() => _cached(
        'alternance',
        () => _client.getText('/apprenant/calendrier/${profile!.codeApprenant}/'),
        _html((d) => parseAlternance(d)),
      );

  /// Documents de liaison des 365 derniers jours.
  Stream<List<DocLiaison>> docsLiaison() {
    final format = DateFormat('dd/MM/yyyy');
    final now = DateTime.now();
    return _cached(
      'liaison',
      () => _client.postText('/pedagogie/documents-liaison/lister-ressource/ajax/', {
        'filtrePublication': 'all',
        'filtreDocument': 'all',
        'periodePublication': 'dates',
        'dateDebRecherche': format.format(now.subtract(const Duration(days: 365))),
        'dateFinRecherche': format.format(now.add(const Duration(days: 1))),
      }),
      parseDocsLiaison,
    );
  }

  Stream<({String text, List<DocumentLink> documents})> docLiaisonDetail(int code) => _cached(
        'liaison-$code',
        () => _client.getText('/pedagogie/documents-liaison/detail/$code'),
        _html((d) => parseDocLiaisonDetail(d)),
      );

  Future<({File file, String mimeType})> downloadDocument(DocumentLink link) =>
      _client.downloadDocument(link.path, link.name);

  static String _message(Object e) {
    // Le lien iCal est secret : son identifiant ne doit pas finir dans les journaux.
    final path = e is DioException ? e.requestOptions.uri.path.replaceAll(RegExp(r'/ical/[^/]+'), '/ical/…') : null;
    final where = e is DioException ? ' (${e.requestOptions.method} $path)' : '';
    debugPrint('NetYParéo erreur$where : $e');
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
