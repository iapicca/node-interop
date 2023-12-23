import 'dart:async';
import 'dart:html';
import 'dart:js_util';

import 'package:meta/meta.dart';
import 'package:node_interop/node_interop.dart';
import 'package:node_interop/http.dart';

import '../node_http.dart';
import 'extensions.dart';
import 'handle_response.dart';

typedef HandleResponse = void Function(IncomingMessage);
typedef HandleSendRequest = Future<StreamedResponse> Function(BaseRequest);
typedef HandleSendRedirect = Future<StreamedResponse> Function(Uri, String);

mixin RedirectHandlerMixin on NodeClientBase {
  @override
  @nonVirtual
  Future<StreamedResponse> redirect(
    BaseRequest request,
    StreamedResponse initialResponse,
  ) async {
    var response = initialResponse;
    var method = request.method;
    final knownLocations = <Uri>{};
    for (var i = 1; response.isRedirect && i < request.maxRedirects; i++) {
      knownLocations.add(response.request!.url);
      // // Set method as defined by RFC 2616 section 10.3.4.
      method = response.statusCode == HttpStatus.seeOther && method == 'POST'
          ? 'GET'
          : method;

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

      response = await completer.future;
      if (knownLocations.contains(response.redirectLocation)) {
        throw ClientException('Redirect loop detected.');
      }
      knownLocations.add(response.redirectLocation);
    }

    return response.isRedirect
        ? throw ClientException('Redirect limit exceeded.')
        : response;
  }
}
