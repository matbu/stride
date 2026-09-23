import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'format.dart';

/// Rappel local (sur l'appareil, pas envoyé par un serveur) de la séance du jour, façon Strava —
/// voir `data/notification_scheduler.dart` pour ce qui décide quoi programmer.
const _reminderHour = 8;
const _daysAhead = 7;
const _androidChannelId = 'daily_session';

final _plugin = FlutterLocalNotificationsPlugin();

/// À appeler une fois au démarrage (avant toute programmation de rappel).
Future<void> initNotifications() async {
  tz_data.initializeTimeZones();
  try {
    final here = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(here.identifier));
  } catch (_) {
    // Fuseau introuvable : les rappels partiraient en UTC plutôt que de planter l'app.
  }
  await _plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  ));
}

/// L'OS ne redemande pas si l'utilisateur a déjà répondu : appeler ceci à chaque programmation
/// ne réaffiche rien, donc pas besoin de suivre séparément si c'est la première fois.
Future<void> requestNotificationPermission() async {
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  await _plugin
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
}

/// Programme un rappel à 8h les jours (parmi les `_daysAhead` prochains) où `titlesByDate`
/// (clé `yyyy-MM-dd`) a au moins une séance. Annule et reprogramme tout à chaque appel : pas
/// d'accumulation, pas de rappel périmé si une séance est déplacée ou supprimée entretemps.
Future<void> scheduleSessionReminders(Map<String, List<String>> titlesByDate) async {
  await _plugin.cancelAll();
  final today = dateOnly(DateTime.now());
  for (var i = 0; i < _daysAhead; i++) {
    final day = addDays(today, i);
    final titles = titlesByDate[isoDate(day)];
    if (titles == null || titles.isEmpty) continue;
    final when = tz.TZDateTime(tz.local, day.year, day.month, day.day, _reminderHour);
    if (when.isBefore(tz.TZDateTime.now(tz.local))) continue; // aujourd'hui, 8h déjà passé
    await _plugin.zonedSchedule(
      i, // un id par décalage de jour suffit : tout est annulé et reprogrammé à chaque appel
      'Séance aujourd’hui',
      titles.join(' · '),
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          'Rappel de séance',
          channelDescription: 'Rappel à 8h les jours où une séance est prévue',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
