import 'package:gtfs_binary_dart/gtfs_binary_dart.dart' as g;

class Stop extends g.Stop {
  final String regionId;

  Stop(this.regionId, g.Stop stop)
    : super(
        feedId: stop.feedId,
        gtfsId: stop.gtfsId,
        code: stop.code,
        name: stop.name,
        desc: stop.desc,
        location: stop.location,
        wheelchair: stop.wheelchair,
        isStation: stop.isStation,
        parent: stop.parent,
        routes: stop.routes,
      );
}

extension StopWithRegion on g.Stop {
  Stop withRegion(String regionId) => Stop(regionId, this);
}
