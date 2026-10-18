import 'dart:async';
import 'dart:isolate';

import 'package:gtfs_binary_dart/gtfs_binary_dart.dart' as g;
import 'package:gtfs_binary_flutter/src/models/feed_info.dart';
import 'package:gtfs_binary_flutter/src/multi_binary.dart';
import 'package:gtfs_binary_flutter/src/models/stop.dart';
import 'package:gtfs_binary_flutter/src/models/route.dart';
import 'package:gtfs_binary_flutter/src/models/departure.dart';
import 'package:latlong2/latlong.dart';

/// A wrapper around multiple GTFS Binary files. Use [create] to instantiate.
/// Keeps the files in a documents subdirectory and updates them on demand.
/// Runs processing in a separate thread to not block the UI.
class GtfsWrapper {
  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<Object?>> _activeRequests = {};
  final Map<int, StreamController<Object?>> _activeStreams = {};
  int _requestCounter = 0;
  bool _closed = false;

  GtfsWrapper._(this._commands, this._responses) {
    _responses.listen(_handleResponse);
  }

  static Future<GtfsWrapper> create() async {
    final initPort = RawReceivePort();
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    initPort.handler = (message) {
      final commandPort = message as SendPort;
      connection.complete((ReceivePort.fromRawReceivePort(initPort), commandPort));
    };

    try {
      await Isolate.spawn(_startWrapperIsolate, (initPort.sendPort));
    } on Object {
      initPort.close();
      rethrow;
    }

    final (ReceivePort receivePort, SendPort sendPort) = await connection.future;
    return GtfsWrapper._(sendPort, receivePort);
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _commands.send(ShutdownGtfsWrapper());
      if (_activeStreams.isEmpty && _activeRequests.isEmpty) {
        _responses.close();
      }
    }
  }

  void _handleResponse(dynamic message) {
    final (int id, Object? response) = message as (int, Object?);
    if (_activeStreams.containsKey(id)) {
      final controller = _activeStreams[id]!;
      if (response is RemoteError) {
        controller.addError(response);
        _activeStreams.remove(id);
        controller.close();
      } else if (response is StreamCompleted) {
        _activeStreams.remove(id);
        controller.close();
      } else {
        controller.add(response);
      }
    } else if (_activeRequests.containsKey(id)) {
      final completer = _activeRequests.remove(id)!;
      if (response is RemoteError) {
        completer.completeError(response);
      } else {
        completer.complete(response);
      }
    } else {
      throw StateError("Received a response for an inactive request: $id, $response");
    }
  }

  static void _startWrapperIsolate(SendPort sendPort) async {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    final gtfs = MultiGtfsBinary();
    await gtfs.readFeeds();

    receivePort.listen((message) async {
      if (message is ShutdownGtfsWrapper) {
        receivePort.close();
      } else if (message is WrapperCommand) {
        try {
          switch (message.command) {
            case GtfsBinaryCommand.queryFeeds:
              sendPort.send((message.id, await gtfs.queryFeeds()));
            case GtfsBinaryCommand.queryFeedsToUpdate:
              sendPort.send((message.id, await gtfs.queryFeedsToUpdate()));
            case GtfsBinaryCommand.downloadFeeds:
              await for (final status in gtfs.downloadFeeds(message.arguments[0])) {
                sendPort.send((message.id, status));
              }
              sendPort.send((message.id, StreamCompleted()));
            case GtfsBinaryCommand.updateFeeds:
              await for (final status in gtfs.updateFeeds(message.arguments[0])) {
                sendPort.send((message.id, status));
              }
              sendPort.send((message.id, StreamCompleted()));
            case GtfsBinaryCommand.getStopByGtfsId:
              sendPort.send((message.id, gtfs.getStopByGtfsId(message.arguments[0], message.arguments[1])));
            case GtfsBinaryCommand.findStopsByGtfsId:
              sendPort.send((message.id, gtfs.findStopsByGtfsId(message.arguments[0])));
            case GtfsBinaryCommand.getRouteByGtfsId:
              sendPort.send((message.id, gtfs.getRouteByGtfsId(message.arguments[0], message.arguments[1])));
            case GtfsBinaryCommand.findRoutesByGtfsId:
              sendPort.send((message.id, gtfs.findRoutesByGtfsId(message.arguments[0])));
            case GtfsBinaryCommand.findStopsByName:
              sendPort.send((message.id, gtfs.findStopsByName(message.arguments[0])));
            case GtfsBinaryCommand.findStopsAround:
              sendPort.send((message.id, gtfs.findStopsAround(message.arguments[0], message.arguments[1])));
            case GtfsBinaryCommand.findStopsForBounds:
              sendPort.send((message.id, gtfs.findStopsForBounds(message.arguments[0], message.arguments[1])));
            case GtfsBinaryCommand.getRoutesForStop:
              sendPort.send((message.id, gtfs.getRoutesForStop(message.arguments[0])));
            case GtfsBinaryCommand.findDepartures:
              sendPort.send((
                message.id,
                gtfs.findDepartures(
                  stop: message.arguments[0],
                  now: message.arguments[1],
                  pastSeconds: message.arguments[2],
                  futureSeconds: message.arguments[3],
                ),
              ));
            case GtfsBinaryCommand.findDeparturesForDay:
              sendPort.send((
                message.id,
                gtfs.findDeparturesForDay(message.arguments[0], message.arguments[1], message.arguments[2]),
              ));
          }
        } catch (e) {
          sendPort.send((message.id, RemoteError(e.toString(), '')));
        }
      }
    });
  }

  Future<T> _sendCommand<T>(GtfsBinaryCommand command, List<dynamic> arguments) {
    final completer = Completer<T>.sync();
    final id = _requestCounter++;
    _activeRequests[id] = completer;
    _commands.send(WrapperCommand(id, command, arguments));
    return completer.future;
  }

  Stream<T> _sendStreamCommand<T>(GtfsBinaryCommand command, List<dynamic> arguments) {
    final completer = StreamController<T>();
    final id = _requestCounter++;
    _activeStreams[id] = completer;
    _commands.send(WrapperCommand(id, command, arguments));
    return completer.stream;
  }

  Future<List<FeedInfo>> queryFeeds() => _sendCommand(GtfsBinaryCommand.queryFeeds, []);

  Future<List<FeedInfo>> queryFeedsToUpdate() => _sendCommand(GtfsBinaryCommand.queryFeedsToUpdate, []);

  Stream<UpdateStatus> downloadFeeds(List<String> feedIds) =>
      _sendStreamCommand(GtfsBinaryCommand.downloadFeeds, [feedIds]);

  Stream<UpdateStatus> updateFeeds(List<String> feedIds) =>
      _sendStreamCommand(GtfsBinaryCommand.updateFeeds, [feedIds]);

  Future<Stop?> getStopByGtfsId(String feedId, String gtfsId) =>
      _sendCommand(GtfsBinaryCommand.getStopByGtfsId, [feedId, gtfsId]);

  Future<List<Stop>> findStopsByGtfsId(String gtfsId) => _sendCommand(GtfsBinaryCommand.findStopsByGtfsId, [gtfsId]);

  Future<Route?> getRouteByGtfsId(String feedId, String gtfsId) =>
      _sendCommand(GtfsBinaryCommand.getRouteByGtfsId, [feedId, gtfsId]);

  Future<List<Route>> findRoutesByGtfsId(String gtfsId) => _sendCommand(GtfsBinaryCommand.findRoutesByGtfsId, [gtfsId]);

  Future<List<Stop>> findStopsByName(String query) => _sendCommand(GtfsBinaryCommand.findStopsByName, [query]);

  Future<List<Stop>> findStopsAround(LatLng center, double radiusMeters) =>
      _sendCommand(GtfsBinaryCommand.findStopsAround, [center, radiusMeters]);

  Future<List<Stop>> findStopsForBounds(LatLng southWest, LatLng northEast) =>
      _sendCommand(GtfsBinaryCommand.findStopsAround, [southWest, northEast]);

  Future<List<Route>> getRoutesForStop(Stop stop) => _sendCommand(GtfsBinaryCommand.getRoutesForStop, [stop]);

  Future<List<Departure>> findDepartures({
    required Stop stop,
    DateTime? now,
    int pastSeconds = 0,
    int futureSeconds = 3600,
  }) => _sendCommand(GtfsBinaryCommand.findDepartures, [stop, now, pastSeconds, futureSeconds]);

  Future<List<g.ScheduleItem>> findDeparturesForDay(Route route, Stop stop, DateTime date) =>
      _sendCommand(GtfsBinaryCommand.findDeparturesForDay, [route, stop, date]);
}

class ShutdownGtfsWrapper {}

class StreamCompleted {}

enum GtfsBinaryCommand {
  queryFeeds,
  queryFeedsToUpdate,
  downloadFeeds,
  updateFeeds,
  getStopByGtfsId,
  findStopsByGtfsId,
  getRouteByGtfsId,
  findRoutesByGtfsId,
  findStopsByName,
  findStopsAround,
  findStopsForBounds,
  getRoutesForStop,
  findDepartures,
  findDeparturesForDay,
}

class WrapperCommand {
  final int id;
  final GtfsBinaryCommand command;
  final List<dynamic> arguments;

  const WrapperCommand(this.id, this.command, [this.arguments = const []]);
}
