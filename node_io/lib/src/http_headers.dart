// Copyright (c) 2017, Anatoly Pulyaevskiy. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
import 'dart:io' as io;
import 'dart:js_util' as js_util;

import 'package:node_interop/http.dart';
import 'package:node_interop/js.dart';
import 'package:node_interop/util.dart';

/// List of HTTP header names which can only have single value.
const _singleValueHttpHeaders = [
  'age',
  'authorization',
  'content-length',
  'content-type',
  'date',
  'etag',
  'expires',
  'from',
  'host',
  'if-modified-since',
  'if-unmodified-since',
  'last-modified',
  'location',
  'max-forwards',
  'proxy-authorization',
  'referer',
  'retry-after',
  'user-agent',
];

class ResponseHttpHeaders extends HttpHeaders {
  ResponseHttpHeaders(this._nativeResponse);

  final ServerResponse _nativeResponse;

  bool _mutable = true;

  /// Collection of header names set in native response object.
  final Set<String> _headerNames = <String>{};

  void finalize() {
    _mutable = false;
  }

  void _checkMutable() {
    if (_mutable == false) {
      throw io.HttpException('HTTP headers are not mutable.');
    }
  }

  @override
  dynamic _getHeader(String name) => _nativeResponse.getHeader(name);

  @override
  Iterable<String> _getHeaderNames() => _headerNames;

  @override
  void _removeHeader(String name) {
    _checkMutable();
    _nativeResponse.removeHeader(name);
    _headerNames.remove(name);
  }

  @override
  void _setHeader(String name, value) {
    _checkMutable();
    _nativeResponse.setHeader(name, value);
    _headerNames.add(name);
  }
}

class RequestHttpHeaders extends HttpHeaders {
  final IncomingMessage _request;

  RequestHttpHeaders(this._request);

  @override
  dynamic _getHeader(String name) =>
      js_util.getProperty(_request.headers, name);

  @override
  void _setHeader(String name, dynamic value) =>
      throw io.HttpException('HTTP headers are not mutable.');

  @override
  void _removeHeader(String name) =>
      throw io.HttpException('HTTP headers are not mutable.');

  @override
  Iterable<String> _getHeaderNames() =>
      List<String>.from(objectKeys(_request.headers));
}

/// Proxy to native JavaScript HTTP headers.
abstract class HttpHeaders implements io.HttpHeaders {
  dynamic _getHeader(String name);
  void _setHeader(String name, Object? value);
  void _removeHeader(String name);
  Iterable<String> _getHeaderNames();

  dynamic getHeader(String name) => _getHeader(name);

  @override
  bool get chunkedTransferEncoding =>
      _getHeader(io.HttpHeaders.transferEncodingHeader) == 'chunked';

  @override
  set chunkedTransferEncoding(bool chunked) {
    if (chunked) {
      _setHeader(io.HttpHeaders.transferEncodingHeader, 'chunked');
    } else {
      _removeHeader(io.HttpHeaders.transferEncodingHeader);
    }
  }

  @override
  int get contentLength {
    final value = _getHeader(io.HttpHeaders.contentLengthHeader);
    if (value != null) return int.parse(value);
    return 0;
  }

  @override
  set contentLength(int length) {
    _setHeader(io.HttpHeaders.contentLengthHeader, length);
  }

  @override
  io.ContentType? get contentType {
    if (_contentType != null) return _contentType;
    String? value = _getHeader(io.HttpHeaders.contentTypeHeader);
    if (value == null || value.isEmpty) return null;
    final types = value.split(',');
    _contentType = io.ContentType.parse(types.first);
    return _contentType;
  }

  io.ContentType? _contentType;

  @override
  set contentType(io.ContentType? type) {
    _setHeader(io.HttpHeaders.contentTypeHeader, type.toString());
  }

  @override
  DateTime? get date {
    String? value = _getHeader(io.HttpHeaders.dateHeader);
    if (value == null || value.isEmpty) return null;
    try {
      return io.HttpDate.parse(value);
    } on Exception {
      return null;
    }
  }

  @override
  set date(DateTime? date) {
    _setOrRemoveDate(io.HttpHeaders.dateHeader, date);
  }

  @override
  DateTime? get expires {
    String? value = _getHeader(io.HttpHeaders.expiresHeader);
    if (value == null || value.isEmpty) return null;
    try {
      return io.HttpDate.parse(value);
    } on Exception {
      return null;
    }
  }

  @override
  set expires(DateTime? expires) {
    _setOrRemoveDate(io.HttpHeaders.expiresHeader, expires);
  }

  @override
  String? get host {
    String? value = _getHeader(io.HttpHeaders.hostHeader);
    if (value != null) {
      return value.split(':').first;
    }
    return null;
  }

  @override
  set host(String? host) {
    var hostAndPort = host;
    if (port != null) {
      hostAndPort = '$host:$port';
    }
    _setHeader(io.HttpHeaders.hostHeader, hostAndPort);
  }

  @override
  int? get port {
    String? value = _getHeader(io.HttpHeaders.hostHeader);
    if (value != null) {
      final parts = value.split(':');
      if (parts.length == 2) return int.parse(parts.last);
    }
    return null;
  }

  @override
  set port(int? value) => _setHeader(
        io.HttpHeaders.hostHeader,
        value == null ? host : '$host:$value',
      );

  @override
  DateTime? get ifModifiedSince {
    String? value = _getHeader(io.HttpHeaders.ifModifiedSinceHeader);
    if (value == null || value.isEmpty) return null;
    try {
      return io.HttpDate.parse(value);
    } on Exception {
      return null;
    }
  }

  @override
  set ifModifiedSince(DateTime? ifModifiedSince) {
    _setOrRemoveDate(io.HttpHeaders.ifModifiedSinceHeader, ifModifiedSince);
  }

  /// Sets the header [name] to the formatted [date].
  ///
  /// If [date] is null, this removes the header [name].
  void _setOrRemoveDate(String name, DateTime? date) {
    if (date == null) {
      _removeHeader(name);
    } else {
      _setHeader(name, io.HttpDate.format(date));
    }
  }

  @override
  bool get persistentConnection {
    final connection = _getHeader(io.HttpHeaders.connectionHeader);
    return (connection == 'keep-alive');
  }

  @override
  set persistentConnection(bool persistentConnection) {
    final value = persistentConnection ? 'keep-alive' : 'close';
    _setHeader(io.HttpHeaders.connectionHeader, value);
  }

  bool _isMultiValue(String name) => !_singleValueHttpHeaders.contains(name);

  @override
  List<String>? operator [](String name) {
    name = name.toLowerCase();
    final value = _getHeader(name);
    if (value != null) {
      if (value is String) {
        return _isMultiValue(name) ? value.split(',') : [value];
      } else {
        // Node.js treats `set-cookie` differently from other headers and
        // composes all values in an array.
        return List.unmodifiable(value);
      }
    }
    return null;
  }

  @override
  String? value(String name) {
    final values = this[name];
    if (values == null) return null;
    if (values.length > 1) {
      throw io.HttpException('More than one value for header $name');
    }
    return values[0];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    if (preserveHeaderCase) {
      // new since 2.8
      // not supported on node
      throw UnsupportedError('HttpHeaders.add(preserveHeaderCase: true)');
    } else {
      final existingValues = this[name];
      final values = existingValues != null ? List.from(existingValues) : [];
      values.add(value.toString());
      _setHeader(name, values);
    }
  }

  @override
  void clear() {
    final names = _getHeaderNames();
    for (final name in names) {
      _removeHeader(name);
    }
  }

  @override
  void forEach(void Function(String name, List<String> values) f) {
    final names = _getHeaderNames();
    names.forEach((String name) {
      f(name, this[name]!);
    });
  }

  @override
  void noFolding(String name) {
    throw UnsupportedError('Folding is not supported for Node.');
  }

  @override
  void remove(String name, Object value) {
    // TODO: this could actually be implemented on our side now.
    throw UnsupportedError(
        'Removing individual values not supported for Node.');
  }

  @override
  void removeAll(String name) {
    _removeHeader(name);
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    if (preserveHeaderCase) {
      // new since 2.8
      // not supported on node
      throw UnsupportedError('HttpHeaders.set(preserveHeaderCase: true)');
    } else {
      _setHeader(name, jsify(value));
    }
  }
}
