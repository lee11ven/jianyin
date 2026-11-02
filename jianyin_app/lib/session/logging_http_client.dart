import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// HTTP 统一入口：拦截所有经 [ApiClient] 发出的请求，打印 header / body。
class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;
  int _seq = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = ++_seq;
    _logRequest(id, request);

    final streamed = await _inner.send(request);
    final bytes = await streamed.stream.toBytes();
    _logResponse(id, streamed, bytes);

    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      streamed.statusCode,
      contentLength: bytes.length,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  void _logRequest(int id, http.BaseRequest request) {
    final buf = StringBuffer()
      ..writeln('[HTTP #$id] >>> ${request.method} ${request.url}')
      ..writeln(_formatHeaders(request.headers));
    final body = _requestBody(request);
    if (body != null && body.isNotEmpty) {
      buf.writeln('body: $body');
    } else {
      buf.writeln('body: <empty>');
    }
    debugPrint(buf.toString().trimRight());
  }

  void _logResponse(int id, http.StreamedResponse res, List<int> bytes) {
    final buf = StringBuffer()
      ..writeln(
        '[HTTP #$id] <<< ${res.statusCode} ${res.reasonPhrase ?? ''}'.trimRight(),
      )
      ..writeln(_formatHeaders(res.headers))
      ..writeln('body: ${_decodeBody(bytes)}');
    debugPrint(buf.toString().trimRight());
  }

  static String _formatHeaders(Map<String, String> headers) {
    if (headers.isEmpty) return 'headers: <none>';
    final lines = headers.entries.map((e) => '  ${e.key}: ${e.value}');
    return 'headers:\n${lines.join('\n')}';
  }

  static String? _requestBody(http.BaseRequest request) {
    if (request is http.Request) {
      return request.body;
    }
    return null;
  }

  static String _decodeBody(List<int> bytes) {
    if (bytes.isEmpty) return '<empty>';
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '<binary ${bytes.length} bytes>';
    }
  }

  @override
  void close() => _inner.close();
}
