// Copyright (c) 2018, Anatoly Pulyaevskiy. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'package:meta/meta.dart';
import 'package:http/http.dart';

import 'redirect_handler.dart';
import 'scheme_agent.dart';
import 'request_handler.dart';

abstract class _HttpSchemes {
  static const http = 'http';
  static const https = 'https';
}

/// HTTP client which uses Node.js I/O system.
abstract class NodeClientBase extends BaseClient {
  /// Creates new Node HTTP client.
  ///
  /// If [httpOptions] or [httpsOptions] are provided they are used to create
  /// underlying `HttpAgent` and `HttpsAgent` respectively. These arguments also
  /// take precedence over [keepAlive] and [keepAliveMsecs].
  NodeClientBase({
    required bool keepAlive,
    required int keepAliveMsecs,
  })  : _httpsAgent = SchemeAgent.https(
          keepAlive: keepAlive,
          keepAliveMsecs: keepAliveMsecs,
        ),
        _httpAgent = SchemeAgent.http(
          keepAlive: keepAlive,
          keepAliveMsecs: keepAliveMsecs,
        );

  final SchemeAgent _httpAgent;
  final SchemeAgent _httpsAgent;

  SchemeAgent schemeAgent(BaseRequest request) {
    switch (request.url.scheme) {
      case _HttpSchemes.http:
        return _httpAgent;
      case _HttpSchemes.https:
        return _httpsAgent;
      default:
        throw Exception('unknown scheme in url: ${request.url}');
    }
  }

  @override
  Future<StreamedResponse> send(BaseRequest request);

  Future<StreamedResponse> redirect(
    BaseRequest request,
    StreamedResponse initialResponse,
  );

  @override
  @nonVirtual
  void close() {
    _httpAgent.dispose();
    _httpsAgent.dispose();
  }
}

class NodeClient extends NodeClientBase
    with RequestHandlerMixin, RedirectHandlerMixin {
  NodeClient({
    super.keepAlive = true,
    super.keepAliveMsecs = 100,
  });
}
