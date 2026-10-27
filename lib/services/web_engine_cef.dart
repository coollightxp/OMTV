/// CEF 引擎实现（webview_cef：随包分发 Chromium 内核，不需要系统
/// WebView2 运行时）。仅在 Windows CEF 包（--dart-define=OMTV_CEF=true）
/// 使用；标准包由 CI 用空实现替换本文件，因此这里可以放心依赖
/// package:webview_cef。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:webview_cef/webview_cef.dart';

import 'web_engine.dart';

/// CEF 默认用户数据目录（缓存/Cookie/登录态）。
/// 插件未开放 rootCachePath，CEF 在 Windows 上按官方默认放在
/// `%LOCALAPPDATA%\CEF\User Data`；部分 CEF 版本会按程序名隔离成
/// `%LOCALAPPDATA%\<exe 名>\User Data`，两个候选都清，避免版本差异导致
/// 缓存没清干净。与 WebView2 版同样放当前用户 LocalAppData——标准用户
/// 令牌 100% 可写，不碰 UAC 红线（exe 在 Program Files 时同目录写不进去）
List<String> _cefUserDataPaths() {
  final sep = Platform.pathSeparator;
  final local = Platform.environment['LOCALAPPDATA'] ?? '';
  if (local.isEmpty) {
    // LOCALAPPDATA 缺失（极少数精简系统）：退回 exe 同目录
    final exe = File(Platform.resolvedExecutable);
    return ['${exe.parent.path}${sep}OMTV.CEF'];
  }
  final names = <String>{'CEF'};
  try {
    final file = Platform.resolvedExecutable.split(sep).last;
    final name = file.toLowerCase().endsWith('.exe')
        ? file.substring(0, file.length - 4)
        : file;
    if (name.isNotEmpty) names.add(name);
  } catch (_) {}
  return [for (final n in names) '$local$sep$n$sepUser Data'];
}

/// 初始化 CEF 运行时（main 启动时调用一次）。
/// 行为对齐 WebView2 版：先清缓存，再创建引擎环境。
Future<void> initCefEngine({required String userAgent}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  cleanCefCache();
  try {
    await WebviewManager().initialize(userAgent: userAgent);
  } catch (e) {
    debugPrint('CEF 初始化失败: $e');
  }
}

/// 退出程序前释放 CEF（关闭浏览器与子进程，避免残留进程占资源）
Future<void> quitCefEngine() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  // 初始化失败时插件内部还处于未就绪状态，quit 里有 assert 保护，别硬调
  final manager = WebviewManager();
  if (manager.value) {
    try {
      await manager.quit();
    } catch (_) {}
  }
  // 浏览器与子进程已关闭，退出时清一次缓存（与启动时行为一致）
  cleanCefCache();
}

/// 清理 CEF 缓存目录。
/// [full]=true 整目录删除（仅启动时调用，此时浏览器尚未创建、无锁定）；
/// false 只删缓存类子目录——网页频道切换/退出时调用，保留 Cookies/登录态。
/// 注意：该目录是 CEF 的默认目录，若同机其它 CEF 程序也在使用，删除会
/// 一并清掉它们的缓存（登录态保留）
void cleanCefCache({bool full = true}) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  final sep = Platform.pathSeparator;
  const cacheDirs = [
    'Cache',
    'Code Cache',
    'GPUCache',
    'Service Worker',
    'blob_storage',
    'ShaderCache',
    'GrShaderCache',
  ];
  for (final root in _cefUserDataPaths()) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    if (full) {
      try {
        dir.deleteSync(recursive: true);
        continue;
      } catch (_) {}
    }
    // CEF 的配置文件数据在 Default 子目录下，根目录也可能有若干缓存目录
    for (final name in cacheDirs) {
      for (final path in ['$root${sep}Default$sep$name', '$root$sep$name']) {
        final d = Directory(path);
        if (d.existsSync()) {
          try {
            d.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    }
  }
}

/// 把 flutter_inappwebview 的 callHandler 桥接到 webview_cef 的原生通道。
///
/// 页面脚本（站点脚本/嗅探脚本）统一调用
/// `window.flutter_inappwebview.callHandler(name, arg)`；CEF 的原生注入
/// 只提供 `window.<channel>(msg)`，而且只在创建时注入一次、导航后丢失。
/// 这里在 document-start 用 `external.JavaScriptChannel` 直接转发，
/// 页面侧脚本无需按引擎改写。
const String kCefBridgeShimJs = r'''
(function(){
  if (window.flutter_inappwebview) return;
  window.flutter_inappwebview = {
    callHandler: function(name){
      try {
        var args = Array.prototype.slice.call(arguments, 1);
        var payload = args.length === 1 ? args[0] : args;
        if (payload !== null && typeof payload === 'object') {
          payload = JSON.stringify(payload);
        }
        if (typeof payload !== 'string') {
          payload = String(payload === undefined || payload === null ? '' : payload);
        }
        external.JavaScriptChannel(name, payload, null);
      } catch (e) {}
      return Promise.resolve(null);
    }
  };
})();
''';

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
}) {
  return _CefWebChannelView(
    key: key,
    url: url,
    documentStartScripts: documentStartScripts,
    onCreated: onCreated,
    onLoadStart: onLoadStart,
    onLoadStop: onLoadStop,
    onProgress: onProgress,
    onError: onError,
    onPageCommitVisible: onPageCommitVisible,
    jsHandlers: jsHandlers,
  );
}

class _CefWebChannelView extends StatefulWidget {
  const _CefWebChannelView({
    super.key,
    required this.url,
    required this.documentStartScripts,
    required this.onCreated,
    required this.onLoadStart,
    required this.onLoadStop,
    required this.onProgress,
    required this.onError,
    required this.onPageCommitVisible,
    required this.jsHandlers,
  });

  final String url;
  final List<String> documentStartScripts;
  final void Function(WebChannelController controller) onCreated;
  final void Function(String url) onLoadStart;
  final void Function(String url) onLoadStop;
  final void Function(int progress) onProgress;
  final void Function(String description) onError;
  final VoidCallback onPageCommitVisible;
  final Map<String, WebChannelJsHandler> jsHandlers;

  @override
  State<_CefWebChannelView> createState() => _CefWebChannelViewState();
}

class _CefWebChannelViewState extends State<_CefWebChannelView> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    // document-start 脚本：先装桥接 shim，再注入引擎无关脚本
    // （右键菜单屏蔽等）。CEF 的 LOAD_START 注入在每次导航后重新下发
    final scripts = InjectUserScripts();
    scripts.add(UserScript(kCefBridgeShimJs, ScriptInjectTime.LOAD_START));
    for (final s in widget.documentStartScripts) {
      scripts.add(UserScript(s, ScriptInjectTime.LOAD_START));
    }
    final controller = WebviewManager().createWebView(
      loading: const SizedBox.expand(),
      injectUserScripts: scripts,
    );
    controller.setWebviewListener(WebviewEventsListener(
      // CEF 没有加载进度事件：起播/结束各补一档，供上层判断
      // 「引擎能工作」（否则 WebView2 的运行时缺失判定会误报）
      onLoadStart: (_, url) {
        widget.onProgress(10);
        widget.onLoadStart(url);
      },
      onLoadEnd: (_, url) {
        widget.onProgress(100);
        // CEF 没有 onPageCommitVisible：加载结束时 DOM 已就绪，
        // 此时补一次（上层在这里注入全屏 CSS，避免白屏闪现）
        try {
          widget.onPageCommitVisible();
        } catch (_) {}
        widget.onLoadStop(url);
      },
      onConsoleMessage: (level, message, source, line) {
        if (level >= 4) debugPrint('CEF[$level] $message ($source:$line)');
      },
    ));
    _controller = controller;
    try {
      // 先创建浏览器（开始加载 url），再注册 JS→Dart 通道：
      // setJavaScriptChannels 内部断言浏览器已就绪，必须放在 initialize 之后
      await controller.initialize(widget.url);
      await controller.setJavaScriptChannels({
        for (final entry in widget.jsHandlers.entries)
          JavascriptChannel(
            name: entry.key,
            onMessageReceived: (message) =>
                entry.value(_decodePayload(message.message)),
          ),
      });
      widget.onCreated(_CefChannelController(controller));
    } catch (e) {
      widget.onError('$e');
    }
    if (mounted) setState(() {});
  }

  /// CEF 原生通道用 JSON.stringify 包装首参：`"d0"` / `"{...}"`，
  /// 这里还原成页面脚本原本要传的字符串
  static String _decodePayload(String raw) {
    if (raw.isEmpty) return raw;
    final first = raw[0];
    if (first != '"' && first != '[' && first != '{' && first != 'n') {
      return raw;
    }
    try {
      final v = jsonDecode(raw);
      if (v is String) return v;
    } catch (_) {}
    return raw;
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    if (c != null) unawaited(c.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.expand();
    return ValueListenableBuilder<bool>(
      valueListenable: c,
      builder: (_, ready, __) =>
          ready ? c.webviewWidget : const SizedBox.expand(),
    );
  }
}

class _CefChannelController implements WebChannelController {
  _CefChannelController(this._controller);

  final WebViewController _controller;

  @override
  Future<dynamic> eval(String js) async {
    try {
      // 浏览器未创建完成时直接调用会读未初始化的 browserId
      await _controller.ready;
      // 每次执行脚本前确认 callHandler 桥在当前文档存在：页面导航/文档
      // 重建会清掉全局变量，而 shim 自身幂等，重复注入无副作用
      await _controller.executeJavaScript(kCefBridgeShimJs);
      // 必须 trim：CEF 把代码包成 `return <code>`，脚本字符串以换行开头时
      // 会触发 JS 自动分号插入变成 `return;`，探测脚本的返回值全部丢失
      // （页面仍会执行，但 Dart 侧拿到 null）。超时兜底：脚本抛异常时
      // 原生不会回调，Promise 永远不结束，会让上层注入流程卡死
      return await _controller
          .evaluateJavascript(js.trim())
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> reload() async {
    try {
      await _controller.ready;
      await _controller.reload();
    } catch (_) {}
  }

  @override
  Future<List<int>?> screenshot() async {
    // webview_cef 无原生截图接口，网页频道截图不可用
    return null;
  }

  @override
  void release() {
    unawaited(_controller.dispose().catchError((Object _) {}));
  }
}
