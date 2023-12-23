import 'dart:async';
import 'dart:js_util';

import 'package:node_interop/http.dart';

import '../node_http.dart';
import 'extensions.dart';

typedef HandleResponse = void Function(IncomingMessage);

HandleResponse handleResponse(
  BaseRequest request,
  Completer<StreamedResponse> completer,
) =>
    (response) {
      final controller = StreamController<List<int>>();

      completer.complete(
        StreamedResponse(
          controller.stream,
          response.statusCode.round(),
          request: request,
          headers: response.dartHeaders,
          reasonPhrase: response.statusMessage,
          isRedirect: response.isRedirect,
        ),
      );

      response
          .on('data', allowInterop(controller.addBuffer))
          .on('end', allowInterop(controller.close));
    };
