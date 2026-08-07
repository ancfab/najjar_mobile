// Shared fake http.Client for tests exercising a multipart/form-data
// request (currently only AncApiClient.uploadAvatar). Kept separate from
// the private `_RecordingHttpClient` fixtures in anc_api_client_test.dart/
// auth_service_test.dart, which hard-cast every received request to
// http.Request and would throw a TypeError if handed a
// http.MultipartRequest instead.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Records the single [http.MultipartRequest] it receives and replies with
/// a canned response (or throws, to simulate a transport failure), so
/// tests can assert on exactly what was sent without making a real network
/// call.
class RecordingMultipartHttpClient extends http.BaseClient {
  RecordingMultipartHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.MultipartRequest request)
  _respond;

  http.MultipartRequest? lastRequest;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.MultipartRequest;
    // A real http.Client calls finalize() internally as part of sending —
    // MultipartRequest.finalize() is what sets the multipart Content-Type
    // header (with its boundary parameter) as a side effect, so this must
    // run before lastRequest is inspected for that header, the same as it
    // would for a real request.
    await req.finalize().drain<void>();
    lastRequest = req;
    requestCount++;
    return _respond(req);
  }

  @override
  void close() {}
}

http.StreamedResponse multipartJsonResponse(
  int statusCode,
  Map<String, dynamic> body, {
  required http.MultipartRequest request,
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    statusCode,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

http.StreamedResponse multipartRawResponse(
  int statusCode,
  String body, {
  required http.MultipartRequest request,
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    request: request,
  );
}
