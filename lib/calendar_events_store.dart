import 'package:flutter/foundation.dart';

/// Datenmodell für Tages-Aktivitäten, losgelöst von der Parser-Testseite.
class DayActivity {
  DayActivity({
    required this.date,
    this.rawDate,
    this.midnightOdometer,
    this.cards = const [],
    this.activities = const [],
    this.places = const [],
    this.gnss = const [],
    this.loads = const [],
  });

  final DateTime date;
  final String? rawDate;
  final String? midnightOdometer;
  final List<CardRow> cards;
  final List<ActivityRow> activities;
  final List<PlaceRow> places;
  final List<GnssRow> gnss;
  final List<LoadRow> loads;
}

class CardRow {
  CardRow({
    this.firstName,
    this.lastName,
    this.slot,
    this.type,
    this.country,
    this.number,
    this.expiry,
    this.insertion,
    this.withdrawal,
    this.odoInsertion,
    this.odoWithdrawal,
    this.prevNation,
    this.prevPlate,
    this.prevWithdrawal,
  });

  final String? firstName;
  final String? lastName;
  final String? slot;
  final String? type;
  final String? country;
  final String? number;
  final String? expiry;
  final String? insertion;
  final String? withdrawal;
  final String? odoInsertion;
  final String? odoWithdrawal;
  final String? prevNation;
  final String? prevPlate;
  final String? prevWithdrawal;
}

class ActivityRow {
  ActivityRow({
    this.time,
    this.cardPresent,
    this.team,
    this.role,
    this.activity,
  });

  final String? time;
  final String? cardPresent;
  final String? team;
  final String? role;
  final String? activity;
}

class PlaceRow {
  PlaceRow({
    this.cardType,
    this.cardCountry,
    this.cardNumber,
    this.entryTime,
    this.country,
    this.region,
    this.odometer,
    this.entryType,
    this.gpsTime,
    this.lat,
    this.lon,
  });

  final String? cardType;
  final String? cardCountry;
  final String? cardNumber;
  final String? entryTime;
  final String? country;
  final String? region;
  final String? odometer;
  final String? entryType;
  final String? gpsTime;
  final String? lat;
  final String? lon;
}

class GnssRow {
  GnssRow({
    this.cardType,
    this.cardCountry,
    this.cardNumber,
    this.time,
    this.gpsTime,
    this.lat,
    this.lon,
  });

  final String? cardType;
  final String? cardCountry;
  final String? cardNumber;
  final String? time;
  final String? gpsTime;
  final String? lat;
  final String? lon;
}

class LoadRow {
  LoadRow({
    this.cardType,
    this.cardCountry,
    this.cardNumber,
    this.time,
    this.operationType,
    this.gpsTime,
    this.lat,
    this.lon,
    this.odometer,
  });

  final String? cardType;
  final String? cardCountry;
  final String? cardNumber;
  final String? time;
  final String? operationType;
  final String? gpsTime;
  final String? lat;
  final String? lon;
  final String? odometer;
}

/// Global Store für Kalendereinträge und ihre Inhalte.
class CalendarEventsStore {
  final ValueNotifier<Set<int>> activityDates =
      ValueNotifier<Set<int>>(<int>{});
  final ValueNotifier<Set<int>> alertDates =
      ValueNotifier<Set<int>>(<int>{});
  final ValueNotifier<Set<int>> allDates =
      ValueNotifier<Set<int>>(<int>{});
  final ValueNotifier<Map<int, DayActivity>> activities =
      ValueNotifier<Map<int, DayActivity>>(<int, DayActivity>{});
  final ValueNotifier<Map<int, EventBundle>> events =
      ValueNotifier<Map<int, EventBundle>>(<int, EventBundle>{});

  /// Normalisiert ein Datum auf Y-M-D und gibt einen stabilen Key zurück.
  int keyFromDate(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

  void setActivities(List<DayActivity> list) {
    final map = <int, DayActivity>{};
    for (final d in list) {
      map[keyFromDate(d.date)] = d;
    }
    activities.value = map;
    activityDates.value = map.keys.toSet();
    _syncAll();
  }

  void setEventBundles(List<EventDayBundle> list) {
    final map = <int, EventBundle>{};
    for (final e in list) {
      final key = keyFromDate(e.date);
      final existing = map[key];
      map[key] = existing != null ? existing.merge(e.bundle) : e.bundle;
    }
    events.value = map;
    alertDates.value = map.keys.toSet();
    _syncAll();
  }

  DayActivity? activityFor(DateTime date) {
    return activities.value[keyFromDate(date)];
  }

  EventBundle? eventsFor(DateTime date) {
    return events.value[keyFromDate(date)];
  }

  void _syncAll() {
    allDates.value = {
      ...activityDates.value,
      ...alertDates.value,
    };
  }
}

final calendarEventsStore = CalendarEventsStore();

class EventDayBundle {
  EventDayBundle({required this.date, required this.bundle});
  final DateTime date;
  final EventBundle bundle;
}

class EventBundle {
  EventBundle({
    this.faults = const [],
    this.events = const [],
    this.overSpeeds = const [],
  });

  final List<FaultRecord> faults;
  final List<EventRecord> events;
  final List<OverSpeedRecord> overSpeeds;

  EventBundle merge(EventBundle other) => EventBundle(
        faults: [...faults, ...other.faults],
        events: [...events, ...other.events],
        overSpeeds: [...overSpeeds, ...other.overSpeeds],
      );
}

class FaultRecord {
  FaultRecord({
    this.faultType,
    this.purpose,
    this.begin,
    this.end,
    this.driverBegin,
    this.driverEnd,
    this.coDriverBegin,
    this.coDriverEnd,
  });

  final String? faultType;
  final String? purpose;
  final String? begin;
  final String? end;
  final String? driverBegin;
  final String? driverEnd;
  final String? coDriverBegin;
  final String? coDriverEnd;
}

class EventRecord {
  EventRecord({
    this.eventType,
    this.purpose,
    this.begin,
    this.end,
    this.similarCount,
    this.driverBegin,
    this.driverEnd,
  });

  final String? eventType;
  final String? purpose;
  final String? begin;
  final String? end;
  final String? similarCount;
  final String? driverBegin;
  final String? driverEnd;
}

class OverSpeedRecord {
  OverSpeedRecord({
    this.eventType,
    this.purpose,
    this.begin,
    this.end,
    this.maxSpeed,
    this.avgSpeed,
    this.similarCount,
    this.driverBegin,
  });

  final String? eventType;
  final String? purpose;
  final String? begin;
  final String? end;
  final String? maxSpeed;
  final String? avgSpeed;
  final String? similarCount;
  final String? driverBegin;
}
