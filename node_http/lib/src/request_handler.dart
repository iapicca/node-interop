import 'dart:async';

import 'package:meta/meta.dart';

import 'package:node_interop/buffer.dart';
import 'package:node_interop/util.dart';

import '../node_http.dart';
import 'extensions.dart';
import 'handle_response.dart';

typedef HandleSendRequest = Future<StreamedResponse> Function(BaseRequest);
typedef HandleSendRedirect = Future<StreamedResponse> Function(Uri, String);

mixin RequestHandlerMixin on NodeClientBase {
  @override
  @nonVirtual
  Future<StreamedResponse> send(BaseRequest request) async {
    final completer = Completer<StreamedResponse>();
    final httpAgent = schemeAgent(request);

    final nodeRequest = httpAgent.sendRequest(
      request.options(httpAgent.agent),
      allowInterop(
        handleResponse(request, completer),
      ),
    )..on('error', allowInterop(completer.completeError));

    await for (final byte in request.finalize()) {
      nodeRequest.write(Buffer.from(byte));
    }

    nodeRequest.end();

    final response = await completer.future;
    return response.isRedirect ? await redirect(request, response) : response;
  }
}
