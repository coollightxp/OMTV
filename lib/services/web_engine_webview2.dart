/// WebView2 引擎实现（flutter_inappwebview，Windows 底层为系统 WebView2）
library;

import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'web_engine.dart';
import 'web_env.dart';

/// 构建填充父级的 WebView2 网页控件
Widget buildWebView2ChannelView({
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
  return InAppWebView(
    key: key,
    webViewEnvironment: webViewEnvironment,
    initialUrlRequest: URLRequest(url: WebUri(url)),
    // 默认零 hook 纯净环境；document-start 只注入右键菜单屏蔽等脚本
    initialUserScripts: UnmodifiableListView<UserScript>([
      for (final script in documentStartScripts)
        UserScript(
          source: script,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
    ]),
    initialSettings: InAppWebViewSettings(
      // 网页播放器（如央视频）自动开播，无需用户先点击网页
      mediaPlaybackRequiresUserGesture: false,
      // 安卓退到后台/隐藏窗口后继续播放音频（听电视模式依赖）。
      // 不加这一项 WebView 会随窗口不可见暂停媒体，导致通知卡片
      // 按钮有效但完全没有声音
      allowBackgroundAudioPlaying: true,
      supportZoom: false,
      transparentBackground: false,
      cacheMode: CacheMode.LOAD_DEFAULT,
      // 允许 iframe 内的视频自动播放（央视频播放器在 iframe 内）
      iframeAllow: 'autoplay; fullscreen; encrypted-media',
      iframeAllowFullscreen: true,
      userAgent: kWebChannelUserAgent,
    ),
    onWebViewCreated: (controller) {
      // JS → Flutter 通道：payload 统一转成字符串交给上层
      jsHandlers.forEach((name, handler) {
        controller.addJavaScriptHandler(
          handlerName: name,
          callback: (args) =>
              handler(args.isEmpty ? '' : args.first.toString()),
        );
      });
      onCreated(_WebView2ChannelController(controller));
    },
    onLoadStart: (controller, url) => onLoadStart(url?.toString() ?? ''),
    onLoadStop: (controller, url) {
      onProgress(100);
      onLoadStop(url?.toString() ?? '');
    },
    // 页面开始渲染时立即注入 CSS，避免白屏闪现
    onPageCommitVisible: (controller, url) => onPageCommitVisible(),
    onProgressChanged: (controller, progress) => onProgress(progress),
    onReceivedError: (controller, request, error) {
      // 主文档加载失败才提示（子资源失败不影响播放）
      if (request.isForMainFrame ?? false) onError(error.description);
    },
  );
}

class _WebView2ChannelController implements WebChannelController {
  _WebView2ChannelController(this._controller);

  final InAppWebViewController _controller;

  @override
  Future<dynamic> eval(String js) =>
      _controller.evaluateJavascript(source: js);

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<List<int>?> screenshot() async {
    try {
      return await _controller.takeScreenshot();
    } catch (_) {
      return null;
    }
  }

  @override
  void release() {
    try {
      // 同步方法，关闭原生 WebView2 实例
      _controller.dispose();
    } catch (_) {}
  }
}
