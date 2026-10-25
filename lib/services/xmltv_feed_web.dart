import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Web：浏览器不能直接解 gzip 文件本体，改取未压缩版本
/// （服务端同时提供 `t.xml`，内容与 `t.xml.gz` 完全相同）。
const String _url = 'https://epg.zsdc.eu.org/t.xml';

Future<Uint8List> fetchXmltv(http.Client client, Duration timeout) async {
  final resp = await client.get(Uri.parse(_url)).timeout(timeout);
  if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
    throw StateError('xmltv http ${resp.statusCode}');
  }
  return resp.bodyBytes;
}
