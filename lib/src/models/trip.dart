import 'package:gtfs_binary_dart/gtfs_binary_dart.dart' as g;
import 'package:gtfs_binary_flutter/src/models/route.dart';
import 'package:gtfs_binary_flutter/src/models/stop.dart';
import 'package:latlong2/latlong.dart';

class Trip {
  final String regionId;
  final String gtfsId;
  final Route route;
  final List<LatLng>? path;
  final List<TripStop> stops;
  final g.Accessibility wheelchair;
  final g.Accessibility bikes;

  /// Whether some or all of stop times are approximate (not timepoints).
  final bool approximate;

  /// If not null, departure and arrival times in [stops] should be disregarded, and
  /// this interval should be used instead for every stop.
  final int? frequencySeconds;

  Trip(this.regionId, g.Trip trip)
    : gtfsId = trip.gtfsId,
      route = trip.route.withRegion(regionId),
      path = trip.path,
      stops = trip.stops.map((ts) => TripStop(regionId, ts)).toList(),
      wheelchair = trip.wheelchair,
      bikes = trip.bikes,
      approximate = trip.approximate,
      frequencySeconds = trip.frequencySeconds;
}

extension TripWithRegion on g.Trip {
  Trip withRegion(String regionId) => Trip(regionId, this);
}

class TripStop {
  final Stop stop;
  final String? headsign;
  final DateTime departure;
  final g.PickupDropoff pickup;
  final g.PickupDropoff dropoff;

  TripStop(String regionId, g.TripStop ts)
    : stop = ts.stop.withRegion(regionId),
      headsign = ts.headsign,
      departure = ts.departure,
      pickup = ts.pickup,
      dropoff = ts.dropoff;

  @override
  String toString() => 'TripStop(stop=${stop.name}, headsign=$headsign, departure=$departure)';
}
