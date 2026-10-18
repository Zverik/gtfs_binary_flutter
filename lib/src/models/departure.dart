import 'package:gtfs_binary_flutter/src/models/stop.dart';
import 'package:gtfs_binary_flutter/src/models/trip.dart';
import 'package:gtfs_binary_dart/gtfs_binary_dart.dart' as g;

/// A [Trip] wrapper highlighting one specific stop.
class Departure implements Comparable<Departure> {
  final Trip trip;
  final TripStop stop;
  final bool interval;

  Departure(this.trip, Stop stop)
    : stop = trip.stops.firstWhere((s) => s.stop.feedId == stop.feedId),
      interval = trip.frequencySeconds != null;

  bool shouldDisregardTime() => trip.frequencySeconds != null;

  @override
  int compareTo(Departure other) {
    if (interval) return other.interval ? trip.frequencySeconds!.compareTo(other.trip.frequencySeconds!) : -1;
    if (other.interval) return 1;
    return stop.departure.compareTo(other.stop.departure);
  }

  @override
  String toString() => 'Departure(trip "${trip.gtfsId}", stop "${stop.stop.gtfsId}")';
}

extension DepartureWithRegion on g.Departure {
  Departure withRegion(String regionId) => Departure(trip.withRegion(regionId), stop.stop.withRegion(regionId));
}
