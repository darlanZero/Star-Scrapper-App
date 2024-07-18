import 'package:http/http.dart' as http;

class UserAgentClient extends http.BaseClient {
  final String _userAgent;
  final http.Client _inner;

  UserAgentClient(this._userAgent, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['User-Agent'] = _userAgent;
    return _inner.send(request);
  }
}