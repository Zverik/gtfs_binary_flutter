import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gtfs_binary_dart/gtfs_binary_dart.dart' as g;
import 'package:gtfs_binary_flutter/src/models/feed_info.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gtfs_binary_flutter/src/models/stop.dart';
import 'package:gtfs_binary_flutter/src/models/route.dart';
import 'package:gtfs_binary_flutter/src/models/departure.dart';

class FeedNotFound implements Exception {
  String feedName;

  FeedNotFound(this.feedName);

  @override
  String toString() => 'Feed not found: $feedName';
}

enum UpdateStep { downloading, updating, loading, done }

class UpdateStatus {
  final String feedId;
  final UpdateStep step;
  final int processed;
  final int total;

  const UpdateStatus(this.feedId, this.step, this.processed, this.total);
}

/// Storage for multiple GTFS Binary feeds. Makes requests synchronously,
/// needs to be called in an isolate: see [GtfsWrapper].
/// Keeps the files in a documents subdirectory and updates them on demand.
class MultiGtfsBinary {
  static final _logger = Logger("MultiGtfsBinary");
  static const _endpoint = 'gtb.osmz.ee';

  final Map<String, g.GtfsBinary> _feeds = {};
  final _dio = Dio();

  /// Loads feeds from the local directory. Should be called after the object creation.
  Future<void> readFeeds() async {
    final dir = await _getGtbDirectory();
    await for (final file in dir.list()) {
      if (file is File && file.path.endsWith(".gtb")) {
        String fileName = file.path.split('/').last;
        String feedName = fileName.substring(0, fileName.lastIndexOf('.'));
        try {
          final access = g.BinaryFileReader(await file.open());
          final feed = g.GtfsBinary.read(access).withFile(access);
          _feeds[feedName] = feed;
        } on FileSystemException catch (e) {
          _logger.warning('Failed to open $file, removing it', e);
          try {
            await file.delete();
          } on FileSystemException catch (e) {
            _logger.severe('Could not delete ${file.path}', e);
          }
        }
      }
    }
  }

  Future<File> _getGtbFile(String feedId) async {
    final dir = await _getGtbDirectory();
    return File("${dir.path}/$feedId.gtb");
  }

  /// Downloads feed information from the server.
  Future<List<FeedInfo>> queryFeeds() async {
    final result = <FeedInfo>[];
    final response = await _dio.get("https://$_endpoint/gtb/feeds.json");
    if (response.statusCode != 200) {
      _logger.warning('HTTP ${response.statusCode} when querying ${response.realUri}');
    } else {
      final data = json.decode(response.data.toString());
      if (data is! Map || !data.containsKey('diffs')) {
        _logger.warning('Wrong json downloaded for feeds: $data');
      } else {
        for (final entry in data.entries) {
          final p = entry.value as Map;
          final bbox = p['bbox'] as List;
          result.add(
            FeedInfo(
              feedId: entry.key,
              version: p['version'],
              date: DateTime.parse(p['date']),
              southWest: LatLng(bbox[0], bbox[1]),
              northEast: LatLng(bbox[2], bbox[3]),
              hasShapes: p['has_shapes'] ?? false,
              title: p['title'],
              titleEn: p['title_en'],
            ),
          );
        }
      }
    }
    return result;
  }

  /// Compares versions for all the feeds we have with the server versions.
  /// Returns a list of feed names that can be updated.
  Future<List<FeedInfo>> queryFeedsToUpdate() async {
    final result = <FeedInfo>[];
    for (final feedId in _feeds.keys) {
      FeedInfo info = _feeds[feedId]!.getFeedInfo(feedId);
      final response = await _dio.get("https://$_endpoint/gtb/diff/$feedId/versions.json");
      if (response.statusCode != 200) {
        _logger.warning('HTTP ${response.statusCode} when querying ${response.realUri}');
      } else {
        final data = json.decode(response.data.toString());
        if (data is! Map || !data.containsKey('diffs')) {
          _logger.warning('Wrong json downloaded for $feedId: $data');
        } else {
          info = info.withLatestVersion(data['latest']);
        }
      }
      result.add(info);
    }
    return result;
  }

  /// Downloads feeds listed.
  Stream<UpdateStatus> downloadFeeds(List<String> feedIds) async* {
    int count = 0;
    final tmpDir = await getTemporaryDirectory();
    for (final feedId in feedIds) {
      yield UpdateStatus(feedId, UpdateStep.downloading, count, feedIds.length);
      final tmpFile = "${tmpDir.path}/updating.gtb";
      final response = await _dio.download("https://$_endpoint/gtb/$feedId.gtb", tmpFile);

      if (response.statusCode != 200) {
        _logger.warning('Could not download ${response.realUri}');
      } else {
        if (_feeds.containsKey(feedId)) {
          yield UpdateStatus(feedId, UpdateStep.updating, count, feedIds.length);
          _feeds[feedId]!.access?.close();
          _feeds.remove(feedId);
        }

        final file = File(tmpFile);
        final gtb = await _getGtbFile(feedId);
        try {
          await gtb.delete();
        } on FileSystemException {
          // File missing, it's fine.
        }
        await file.rename(gtb.path);

        yield UpdateStatus(feedId, UpdateStep.loading, count, feedIds.length);
        final access = g.BinaryFileReader(await gtb.open());
        _feeds[feedId] = g.GtfsBinary.read(access).withFile(access);
      }

      count++;
      yield UpdateStatus(feedId, UpdateStep.done, count, feedIds.length);
    }
  }

  /// Updates feeds listed.
  Stream<UpdateStatus> updateFeeds(List<String> feedIds) async* {
    int count = 0;
    final tmpDir = await getTemporaryDirectory();
    for (final feedId in feedIds) {
      yield UpdateStatus(feedId, UpdateStep.downloading, count, feedIds.length);
      final version = _feeds[feedId]!.footer.version;
      final tmpFile = "${tmpDir.path}/updating.diff";
      bool isDiff = true;
      var response = await _dio.download("https://$_endpoint/gtb/diff/$feedId/$version.diff", tmpFile);
      if (response.statusCode != 200) {
        response = await _dio.download("https://$_endpoint/gtb/$feedId.gtb", tmpFile);
        isDiff = false;
      }
      if (response.statusCode != 200) {
        _logger.warning('Could not download ${response.realUri}');
      } else {
        yield UpdateStatus(feedId, UpdateStep.updating, count, feedIds.length);
        _feeds[feedId]!.access?.close();
        _feeds.remove(feedId);

        final file = File(tmpFile);
        final gtb = await _getGtbFile(feedId);
        if (isDiff) {
          await _updateFeed(feedId, file);
          await file.delete();
        } else {
          await gtb.delete();
          await file.rename(gtb.path);
        }

        yield UpdateStatus(feedId, UpdateStep.loading, count, feedIds.length);
        final access = g.BinaryFileReader(await gtb.open());
        _feeds[feedId] = g.GtfsBinary.read(access).withFile(access);
      }

      count++;
      yield UpdateStatus(feedId, UpdateStep.done, count, feedIds.length);
    }
  }

  /// Applies bsdiff to the feed file.
  Future<void> _updateFeed(String feedId, File delta) async {
    // TODO: close the feed and run bsdiff, then open the feed.
  }

  Future<Directory> _getGtbDirectory() async {
    final docs = await getApplicationSupportDirectory();
    final gtbs = Directory('${docs.path}/gtb');
    if (!await gtbs.exists()) {
      await gtbs.create(recursive: true);
    }
    return gtbs;
  }

  Stop? getStopByGtfsId(String feedId, String gtfsId) {
    if (!_feeds.containsKey(feedId)) {
      throw FeedNotFound(feedId);
    }
    return _feeds[feedId]!.getStopByGtfsId(gtfsId)?.withRegion(feedId);
  }

  List<Stop> findStopsByGtfsId(String gtfsId) {
    return _feeds.entries
        .map((entry) => entry.value.getStopByGtfsId(gtfsId)?.withRegion(entry.key))
        .whereType<Stop>()
        .toList();
  }

  Route? getRouteByGtfsId(String feedId, String gtfsId) {
    if (!_feeds.containsKey(feedId)) {
      throw FeedNotFound(feedId);
    }
    return _feeds[feedId]!.getRouteByGtfsId(gtfsId)?.withRegion(feedId);
  }

  List<Route> findRoutesByGtfsId(String gtfsId) {
    return _feeds.entries
        .map((entry) => entry.value.getRouteByGtfsId(gtfsId)?.withRegion(entry.key))
        .whereType<Route>()
        .toList();
  }

  List<Stop> findStopsByName(String query) {
    return _feeds.entries
        .map((entry) => entry.value.autocompleteStops(query).map((s) => s.withRegion(entry.key)))
        .reduce((a, b) => a.followedBy(b))
        .toList();
  }

  List<Stop> findStopsAround(LatLng center, double radiusMeters) {
    return _feeds.entries
        .map((entry) => entry.value.findStopsAround(center, radiusMeters).map((s) => s.withRegion(entry.key)))
        .reduce((a, b) => a.followedBy(b))
        .toList();
  }

  List<Stop> findStopsForBounds(LatLng southWest, LatLng northEast) {
    return _feeds.entries
        .map((entry) => entry.value.findStopsForBounds(southWest, northEast).map((s) => s.withRegion(entry.key)))
        .reduce((a, b) => a.followedBy(b))
        .toList();
  }

  List<Route> getRoutesForStop(Stop stop) {
    if (!_feeds.containsKey(stop.regionId)) {
      throw FeedNotFound(stop.regionId);
    }
    return _feeds[stop.regionId]!.getRoutesForStop(stop).map((r) => r.withRegion(stop.regionId)).toList();
  }

  List<Departure> findDepartures({required Stop stop, DateTime? now, int pastSeconds = 0, int futureSeconds = 3600}) {
    if (!_feeds.containsKey(stop.regionId)) {
      throw FeedNotFound(stop.regionId);
    }
    return _feeds[stop.regionId]!
        .findDepartures(stop: stop, now: now, pastSeconds: pastSeconds, futureSeconds: futureSeconds)
        .map((d) => d.withRegion(stop.regionId))
        .toList();
  }

  List<g.ScheduleItem> findDeparturesForDay(Route route, Stop stop, DateTime date) {
    if (!_feeds.containsKey(stop.regionId)) {
      throw FeedNotFound(stop.regionId);
    }
    return _feeds[stop.regionId]!.findDeparturesForDay(route, stop, g.JustDate.fromDateTime(date));
  }
}
