import 'package:node_interop/http.dart';
import 'package:node_interop/https.dart';

typedef SendRequest = ClientRequest Function(
  RequestOptions, [
  void Function(IncomingMessage),
]);

typedef VoidCallback = void Function();

abstract class SchemeAgent {
  HttpAgent get agent;
  SendRequest get sendRequest;

  factory SchemeAgent.http({
    required bool keepAlive,
    required int keepAliveMsecs,
  }) =>
      _SchemeAgentHttp(
        keepAlive: keepAlive,
        keepAliveMsecs: keepAliveMsecs,
      );

  factory SchemeAgent.https({
    required bool keepAlive,
    required int keepAliveMsecs,
  }) =>
      _SchemeAgentHttps(
        keepAlive: keepAlive,
        keepAliveMsecs: keepAliveMsecs,
      );

  @override
  operator ==(other) => other is SchemeAgent && other.hashCode == hashCode;

  @override
  int get hashCode => Object.hash(agent, sendRequest);

  VoidCallback get dispose;
}

class _SchemeAgentHttp implements SchemeAgent {
  @override
  final HttpAgent agent;
  @override
  final SendRequest sendRequest = http.request;
  _SchemeAgentHttp({
    required bool keepAlive,
    required int keepAliveMsecs,
  }) : agent = createHttpAgent(HttpAgentOptions(
          keepAlive: keepAlive,
          keepAliveMsecs: keepAliveMsecs,
        ));

  @override
  VoidCallback get dispose => agent.destroy;
}

class _SchemeAgentHttps implements SchemeAgent {
  @override
  final HttpAgent agent;
  @override
  final SendRequest sendRequest = https.request;
  _SchemeAgentHttps({
    required bool keepAlive,
    required int keepAliveMsecs,
  }) : agent = createHttpsAgent(HttpsAgentOptions(
          keepAlive: keepAlive,
          keepAliveMsecs: keepAliveMsecs,
        ));

  @override
  VoidCallback get dispose => agent.destroy;
}
