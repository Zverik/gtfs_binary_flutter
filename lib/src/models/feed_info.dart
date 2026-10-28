import 'package:gtfs_binary_dart/gtfs_binary_dart.dart';
import 'package:latlong2/latlong.dart';

class FeedInfo {
  final String feedId;
  final int? installedVersion;
  final int? latestVersion;
  final DateTime date;
  final LatLng southWest;
  final LatLng northEast;
  final bool hasShapes;
  final String? title;
  final String? titleEn;

  const FeedInfo({
    required this.feedId,
    this.installedVersion,
    this.latestVersion,
    required this.date,
    required this.southWest,
    required this.northEast,
    required this.hasShapes,
    this.title,
    this.titleEn,
  });

  FeedInfo withLatestVersion(int latestVersion) => FeedInfo(
    feedId: feedId,
    installedVersion: installedVersion,
    latestVersion: latestVersion,
    date: date,
    southWest: southWest,
    northEast: northEast,
    hasShapes: hasShapes,
    title: title,
    titleEn: titleEn,
  );

  bool get needUpdate => installedVersion != null && installedVersion! < (latestVersion ?? installedVersion!);

  bool get isInstalled => installedVersion != null;

  bool contains(LatLng point) =>
      point.latitude >= southWest.latitude &&
      point.latitude <= northEast.latitude &&
      point.longitude >= southWest.longitude &&
      point.longitude <= northEast.longitude;
}

extension GtfsBinaryFeedInfo on GtfsBinary {
  FeedInfo getFeedInfo(String feedId) => FeedInfo(
    feedId: feedId,
    installedVersion: footer.build,
    date: DateTime(footer.date ~/ 10000, (footer.date ~/ 100) % 100, footer.date % 100),
    southWest: LatLng(footer.bboxLatLon[0] / 100.0, footer.bboxLatLon[1] / 100.0),
    northEast: LatLng(footer.bboxLatLon[2] / 100.0, footer.bboxLatLon[3] / 100.0),
    hasShapes: shapes != null,
    title: footer.title.isEmpty ? null : footer.title,
    titleEn: footer.titleEn.isEmpty ? null : footer.titleEn,
  );
}
