/// 网页通道引擎抽象层。
///
/// - 标准包（Windows/Android/iOS/macOS）：flutter_inappwebview，
///   Windows 底层是系统 WebView2 运行时；
/// - Windows CEF 包：webview_cef（随包分发 Chromium 内核，不依赖系统
///   WebView2），编译时加 --dart-define=OMTV_CEF=true 切换。
///
/// 两套引擎的 Dart API 差异全部收敛在本层，播放器界面只面向
/// [WebChannelController] 与 [buildWebChannelView] 编程。
library;

import 'package:flutter/widgets.dart';

// CEF 实现依赖 dart:io + webview_cef 原生插件，Web 平台加载空实现
import 'web_engine_cef_stub.dart'
    if (dart.library.io) 'web_engine_cef.dart' as cef;
import 'web_engine_webview2.dart' as wv2;
import 'web_env.dart';

/// 桌面端伪装 Chrome 的 UA（安卓 WebView 若被识别为移动端，
/// 部分站点会重定向到「下载 App」页）
const String kWebChannelUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// true = 当前安装包使用 CEF 内核（Windows CEF 包）
const bool kUseCefWebEngine = bool.fromEnvironment('OMTV_CEF');

/// 网页通道控制桥（WebView2 / CEF 共用的最小接口）
abstract class WebChannelController {
  /// 执行 JS 并返回结果（页面探测/嗅探依赖返回值）
  Future<dynamic> eval(String js);

  /// 重新加载当前网页（卡死自愈用）
  Future<void> reload();

  /// 网页截图 PNG 字节；引擎不支持时返回 null
  Future<List<int>?> screenshot();

  /// 销毁原生控件（调用后不可再用）
  void release();
}

/// 页面内 JS 消息：payload 为消息正文（统一转成字符串）
typedef WebChannelJsHandler = void Function(String payload);

Widget buildWebChannelView({
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
  if (kUseCefWebEngine) {
    return cef.buildCefWebChannelView(
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
  return wv2.buildWebView2ChannelView(
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

/// 启动时初始化网页引擎（WebView2 环境 / CEF 运行时）。
/// 与退出清理成对调用，保证两套包的启动/退出行为一致。
Future<void> initWebChannelEngine() async {
  if (kUseCefWebEngine) {
    await cef.initCefEngine(userAgent: kWebChannelUserAgent);
    return;
  }
  // 启动前清理 WebView2 缓存，避免旧缓存导致网页频道加载慢/卡旧画面
  cleanWebView2Cache();
  // 创建自定义 WebView2 环境，禁用磁盘缓存 + 允许无手势自动播放
  await initWebViewEnvironment();
}

/// 清理网页引擎缓存。[full]=true 整目录删除（仅启动/退出调用），
/// false 只删缓存类子目录（网页频道切换中调用，避免阻塞主线程）
void cleanWebChannelCache({bool full = true}) {
  if (kUseCefWebEngine) {
    cef.cleanCefCache(full: full);
    return;
  }
  cleanWebView2Cache(full: full);
}

/// 退出程序前释放引擎（关闭 CEF 浏览器/子进程；WebView2 版由
/// PlayerScreen.onWindowClose 释放 webViewEnvironment）
Future<void> quitWebChannelEngine() async {
  if (kUseCefWebEngine) {
    await cef.quitCefEngine();
  }
}
