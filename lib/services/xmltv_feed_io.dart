import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 原生平台（Windows/Android/iOS/macOS/Linux）：下载 gzip 版 XMLTV 并解压，
/// 体积约 470KB（解开后约 6.9MB）。
const String _url = 'https://epg.zsdc.eu.org/t.xml.gz';

const Map<String, String> _headers = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  'Accept': 'application/gzip,application/xml',
};

Future<Uint8List> fetchXmltv(http.Client client, Duration timeout) async {
  final resp = await client
      .get(Uri.parse(_url), headers: _headers)
      .timeout(timeout);
  if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
    throw StateError('xmltv http ${resp.statusCode}');
  }
  return Uint8List.fromList(gzip.decode(resp.bodyBytes));
}
