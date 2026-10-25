/// 按平台选择 XMLTV 下载实现：原生平台解 gzip，Web 取未压缩 XML。
export 'xmltv_feed_web.dart' if (dart.library.io) 'xmltv_feed_io.dart';
