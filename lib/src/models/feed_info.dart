import 'package:gtfs_binary_dart/gtfs_binary_dart.dart';
import 'package:latlong2/latlong.dart';

class FeedInfo {
  final String feedId;
  final int version;
  final int? latestVersion;
  final DateTime date;
  final LatLng southWest;
  final LatLng northEast;
  final bool hasShapes;
  final String? title;
  final String? titleEn;

  const FeedInfo({
    required this.feedId,
    required this.version,
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
    version: version,
    latestVersion: latestVersion,
    date: date,
    southWest: southWest,
    northEast: northEast,
    hasShapes: hasShapes,
    title: title,
    titleEn: titleEn,
  );

  bool get needUpdate => version < (latestVersion ?? version);
}

extension GtfsBinaryFeedInfo on GtfsBinary {
  FeedInfo getFeedInfo(String feedId) => FeedInfo(
    feedId: feedId,
    version: footer.build,
    date: DateTime(footer.date ~/ 10000, (footer.date ~/ 100) % 100, footer.date % 100),
    southWest: LatLng(footer.bboxLatLon[0] / 100.0, footer.bboxLatLon[1] / 100.0),
    northEast: LatLng(footer.bboxLatLon[2] / 100.0, footer.bboxLatLon[3] / 100.0),
    hasShapes: shapes != null,
    title: footer.title.isEmpty ? null : footer.title,
    titleEn: footer.titleEn.isEmpty ? null : footer.titleEn,
  );
}