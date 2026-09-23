import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../core/netypareo_client.dart';
import 'models.dart';
import 'notifications.dart';
import 'parsers.dart';
import 'planning_diff.dart';

const kSecure = FlutterSecureStorage();
const kIcalKey = 'icalUrl';
const kProfileKey = 'profile';
const kSeancesKey = 'seances';
const kLastSyncKey = 'lastSync';
const kAlertsKey = 'alerts';

const _task = 'planning-sync';

/// Le planning en cache, partagé entre l'application et la synchronisation en arrière-plan.
class PlanningStore {
  PlanningStore._();

  static List<Seance>? read(SharedPreferences prefs) {
    final cached = prefs.getString(kSeancesKey);
    if (cached == null) return null;
    return (jsonDecode(cached) as List).map((e) => Seance.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Enregistre la nouvelle version et renvoie ce qui a changé depuis la dernière enregistrée,
  /// par l'application ou par la tâche de fond (d'où le `reload`).
  static Future<List<SeanceChange>> save(SharedPreferences prefs, List<Seance> fresh) async {
    await prefs.reload();
    final previous = read(prefs);
    final now = DateTime.now();
    if (fresh.isEmpty && (previous ?? const []).any((s) => s.end.isAfter(now))) {
      // Un flux vide alors qu'il restait des cours : incident côté serveur, on garde l'ancien planning.
      throw const NetypareoException('NetYParéo a renvoyé un planning vide.');
    }
    await prefs.setString(kSeancesKey, jsonEncode(fresh.map((s) => s.toJson()).toList()));
    await prefs.setString(kLastSyncKey, now.toIso8601String());
    return previous == null ? const [] : diffSeances(previous, fresh, now: now);
  }
}

/// Synchronisation périodique du planning, application fermée (WorkManager, 15 min au minimum).
class BackgroundSync {
  BackgroundSync._();

  static Future<void> init() => Workmanager().initialize(callbackDispatcher);

  static Future<void> schedule() => Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );

  static Future<void> cancel() => Workmanager().cancelByUniqueName(_task);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(kAlertsKey) ?? true)) return true;
      final url = await kSecure.read(key: kIcalKey);
      final profile = prefs.getString(kProfileKey);
      if (url == null || profile == null) return true;
      await initializeDateFormatting('fr_FR');
      final client = await NetypareoClient.create();
      final code = Profile.fromJson(jsonDecode(profile) as Map<String, dynamic>).codeApprenant;
      final fresh = parseIcal(await client.getPublicText(url), codeApprenant: code);
      await PlanningNotifications.showChanges(await PlanningStore.save(prefs, fresh));
      return true;
    } catch (e) {
      debugPrint('Synchronisation en arrière-plan : $e');
      return false;
    }
  });
}
