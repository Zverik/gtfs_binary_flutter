import 'package:gtfs_binary_dart/gtfs_binary_dart.dart' as g;

class Route extends g.Route {
  final String regionId;

  Route(this.regionId, g.Route route)
    : super(
        feedId: route.feedId,
        agency: route.agency,
        type: route.type,
        name: route.name,
        longName: route.longName,
        desc: route.desc,
        color: route.color,
        textColor: route.textColor,
        headsigns: route.headsigns,
      );
}

extension RouteWithRegion on g.Route {
  Route withRegion(String regionId) => Route(regionId, this);
}
