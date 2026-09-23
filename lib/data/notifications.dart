import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../ui/format.dart';
import 'models.dart';
import 'planning_diff.dart';

/// Ce qu'une notification demande d'ouvrir : un jour du planning, et la séance si elle existe encore.
class OpenRequest {
  const OpenRequest({required this.day, this.uid});

  final DateTime day;
  final String? uid;

  String toPayload() => jsonEncode({'day': day.toIso8601String(), 'uid': uid});

  static OpenRequest? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      return OpenRequest(day: DateTime.parse(json['day'] as String), uid: json['uid'] as String?);
    } catch (_) {
      return null;
    }
  }
}

/// Notifications locales des changements de planning.
class PlanningNotifications {
  PlanningNotifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Le dernier cours demandé par un appui sur une notification ; l'interface l'écoute.
  static final openRequests = ValueNotifier<OpenRequest?>(null);

  /// Au-delà, une seule notification résume tout (rentrée, nouveau semestre...).
  static const _maxDetailed = 4;

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_launcher_monochrome')),
      onDidReceiveNotificationResponse: (response) =>
          openRequests.value = OpenRequest.fromPayload(response.payload),
    );
    _ready = true;
  }

  /// Si l'application a été lancée par un appui sur une notification.
  static Future<void> checkLaunch() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      openRequests.value = OpenRequest.fromPayload(details!.notificationResponse?.payload);
    }
  }

  /// Android 13 et plus : demande l'autorisation d'afficher des notifications.
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static Future<void> showChanges(List<SeanceChange> changes) async {
    if (changes.isEmpty) return;
    await init();
    if (changes.length > _maxDetailed) {
      final first = changes.first.seance.start;
      await _show(
        0,
        '${changes.length} changements dans ton planning',
        _summary(changes),
        OpenRequest(day: first),
      );
      return;
    }
    for (final change in changes) {
      final (title, body) = describe(change);
      await _show(
        change.seance.uid.hashCode & 0x7fffffff,
        title,
        body,
        OpenRequest(day: change.seance.start, uid: change.kind == ChangeKind.removed ? null : change.seance.uid),
      );
    }
    // Sans résumé à nous, Android groupe tout seul et un appui sur le groupe n'ouvre rien de précis.
    if (changes.length > 1) {
      await _show(
        0,
        '${changes.length} changements dans ton planning',
        _summary(changes),
        OpenRequest(day: changes.first.seance.start),
        summary: true,
      );
    }
  }

  static Future<void> _show(int id, String title, String body, OpenRequest open, {bool summary = false}) =>
      _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: open.toPayload(),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'planning_changes',
            'Changements de planning',
            channelDescription: 'Cours ajoutés, retirés ou modifiés',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.event,
            icon: 'ic_launcher_monochrome',
            color: const Color(0xFF6D5BF7),
            styleInformation: BigTextStyleInformation(body),
            groupKey: 'planning',
            setAsGroupSummary: summary,
          ),
        ),
      );

  static String _summary(List<SeanceChange> changes) {
    int count(ChangeKind k) => changes.where((c) => c.kind == k).length;
    final parts = [
      if (count(ChangeKind.added) > 0) '${count(ChangeKind.added)} ajouté(s)',
      if (count(ChangeKind.removed) > 0) '${count(ChangeKind.removed)} retiré(s)',
      if (count(ChangeKind.modified) > 0) '${count(ChangeKind.modified)} modifié(s)',
    ];
    return 'Cours ${parts.join(', ')}. Touche pour voir le planning.';
  }

  /// Titre et texte d'une notification, en français.
  static (String, String) describe(SeanceChange change) {
    final s = change.seance;
    final subject = capitalizeWords(s.subject);
    switch (change.kind) {
      case ChangeKind.added:
        return (
          'Cours ajouté : $subject',
          [_when(s), if (s.room.isNotEmpty) 'Salle ${s.room}', if (s.teachers.isNotEmpty) s.teachers].join('\n'),
        );
      case ChangeKind.removed:
        return ('Cours retiré : $subject', '${_when(s)}\nCe cours n\'est plus dans ton planning.');
      case ChangeKind.modified:
        final b = change.before!;
        final lines = [
          if (change.timeChanged) 'Horaire : ${_when(b)} → ${_when(s)}' else _when(s),
          if (change.roomChanged) 'Salle : ${_or(b.room)} → ${_or(s.room)}',
          if (change.teachersChanged) 'Formateur : ${_or(b.teachers)} → ${_or(s.teachers)}',
          if (change.subjectChanged) 'Matière : ${capitalizeWords(b.subject)} → $subject',
        ];
        return ('Cours modifié : $subject', lines.join('\n'));
    }
  }

  static String _or(String value) => value.isEmpty ? 'aucun' : value;

  static String _when(Seance s) {
    final day = DateFormat('EEE d MMM', 'fr_FR').format(s.start);
    final hours = '${DateFormat.Hm('fr_FR').format(s.start)}–${DateFormat.Hm('fr_FR').format(s.end)}';
    return '$day, $hours';
  }
}
