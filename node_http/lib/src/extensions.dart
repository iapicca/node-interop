import 'dart:async';
import 'dart:js_util' as js_util;

import 'package:node_http/node_http.dart';
import 'package:node_interop/http.dart';
import 'package:node_io/node_io.dart';

extension PathWithQueryX on Uri {
  String get pathWithQuery => hasQuery ? [path, '?', query].join() : path;
}

extension RequestOptionsX on BaseRequest {
  RequestOptions options(HttpAgent agent) => RequestOptions(
        protocol: '${url.scheme}:',
        hostname: url.host,
        port: url.port,
        method: method,
        path: url.pathWithQuery,
        headers: headers,
        agent: agent,
      );
}

extension DartHeadersX on IncomingMessage {
  Map<String, String> get dartHeaders => {
        for (final entry
            in (js_util.dartify(headers) as Map<String, Object?>).entries)
          entry.key: entry.value is List
              ? [for (final value in entry.value as List) '$value'].join(',')
              : '${entry.value}'
      };
}

extension IsRedirectX on IncomingMessage {
  bool get isRedirect {
    switch (method) {
      case 'GET' || 'HEAD':
        return [
          HttpStatus.movedPermanently,
          HttpStatus.found,
          HttpStatus.seeOther,
          HttpStatus.temporaryRedirect,
        ].contains(statusCode);
      case 'POST':
        return statusCode == HttpStatus.seeOther;
      default:
        return false;
    }
  }
}

extension AddBufferX on StreamController<List<int>> {
  void addBuffer(Iterable<int> buffer) => add(List.unmodifiable(buffer));
}

extension RedirectLocationX on StreamedResponse {
  Uri get redirectLocation {
    final location = headers[HttpHeaders.locationHeader];
    return location == null
        ? (throw StateError('Response has no Location header for redirect.'))
        : Uri.parse(location);
  }
}

// extension LocationsFromRedirectInfo on Iterable<RedirectInfo> {
//   Iterable<Uri> get locations sync* {
//     for (final info in this) {
//       yield info.location;
//     }
//   }
// }
