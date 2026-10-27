/// 标准包的 CEF 空实现（CI 构建时临时替换 lib/services/web_engine_cef.dart）。
///
/// CEF 插件 DLL 静态依赖 libcef.dll，没随包携带内核的包不能链接它；
/// 构建时用本文件替换真实实现，构建后从 git 恢复。
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
