import '../lib/node_http.dart' as http;

const _url = 'https://example.com/';
void main() async {
  // For one-off requests.
  final response = await http.get(_url);
  print(response.body);
  // To re-use socket connections:
  final client = http.NodeClient();
  final response2 = await client.get(Uri.parse(_url));
  print(response2.body);
  client.close(); // make sure to close the client when work is done.
}
