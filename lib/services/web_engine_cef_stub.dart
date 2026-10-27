/// CEF 引擎空实现（Web 平台）。
///
/// web 端网页频道走 flutter_inappwebview 的 iframe 实现，webview_cef 与
/// dart:io 在 Web 上均不可用，这里只提供与 web_engine_cef.dart 同签名的
/// 占位实现，保证 web_engine.dart 能按平台条件加载。
library;

import 'package:flutter/widgets.dart';

import 'web_engine.dart';

Future<void> initCefEngine({required String userAgent}) async {}

Future<void> quitCefEngine() async {}

void cleanCefCache({bool full = true}) {}

Widget buildCefWebChannelView({
  Key? key,
  required String url,
  required List<String> documentStartScripts,
  required void Function(WebChannelController controller) onCreated,
  required void Function(String url) onLoadStart,
  required void Function(String url) onLoadStop,
  required void Function(int progress) onProgress,
  required void Function(String description) onError,
  required VoidCallback onPageCommitVisible,
  required Map<String, WebChannelJsHandler> jsHandlers,
}) =>
    const SizedBox.shrink();
