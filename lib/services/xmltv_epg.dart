import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/xmltv_channels.dart';
import '../models/epg_program.dart';
import 'xmltv_feed.dart';

/// XMLTV 节目单 EPG（主源）。
///
/// 数据来源 `https://epg.zsdc.eu.org/t.xml.gz`（XMLTV 标准格式，gzip 压缩，
/// 一次请求即包含全部频道的多天节目单）。
/// 相比逐频道抓 HTML，单请求 + 标准格式更稳定，也不会因页面改版断掉解析。
///
/// 只保留当天的节目（够用且省内存），解析失败/整源不可用时由调用方
/// 回退到央视频 EPG。
class XmltvEpg {
  /// 服务端节目单更新频率不固定，1 小时探测一次即可拿到当天最新数据。
  static const Duration refreshInterval = Duration(hours: 1);

  /// 整份节目单下载 + 解压的超时（弱网/服务端慢时不能让启动流程卡住）
  static const Duration _timeout = Duration(seconds: 12);

  static final RegExp _progRe =
      RegExp(r'<programme\b([^>]*)>([\s\S]*?)</programme>');
  static final RegExp _attrChannelRe = RegExp(r'channel="([^"]*)"');
  static final RegExp _attrStartRe = RegExp(r'start="(\d{14})');
  static final RegExp _attrStopRe = RegExp(r'stop="(\d{14})');
  static final RegExp _titleRe = RegExp(r'<title[^>]*>([\s\S]*?)</title>');

  final http.Client _client;

  /// pid -> 当天节目单（已按开始时间排序）
  final Map<String, List<EpgProgram>> _byPid = {};
  DateTime? _fetchedAt;

  /// 本次运行中是否已判定整源不可用（一旦置位不再重试）
  bool _down = false;

  XmltvEpg({http.Client? client}) : _client = client ?? http.Client();

  List<EpgProgram> programsFor(String pid) => _byPid[pid] ?? const [];

  /// 该频道是否已有 XMLTV 节目单
  bool has(String pid) => _byPid[pid]?.isNotEmpty ?? false;

  bool get isDown => _down;

  bool get isEmpty => _byPid.isEmpty;

  /// 网络恢复后允许重新探测整源（仅用于启动时无网导致的误判）
  void resetDown() {
    _down = false;
  }

  /// 跨天或超过刷新间隔则需要重新下载
  bool get _stale {
    final at = _fetchedAt;
    if (at == null) return true;
    final now = DateTime.now();
    if (at.year != now.year || at.month != now.month || at.day != now.day) {
      return true;
    }
    return now.difference(at) > refreshInterval;
  }

  /// 下载并解析当天节目单。整源失败时标记不可用并返回 0。
  /// 返回值：本次解析出的频道数量。
  Future<int> refresh({
    bool force = false,
    void Function(int done, int total)? onProgress,
  }) async {
    if (_down) return _byPid.length;
    if (!force && !_stale) return _byPid.length;
    try {
      final bytes = await fetchXmltv(_client, _timeout);
      final xml = utf8.decode(bytes, allowMalformed: true);
      final parsed = parse(xml, DateTime.now());
      if (parsed.isEmpty) {
        _down = true;
      } else {
        // 整份替换，避免跨天后残留昨天的节目单
        _byPid
          ..clear()
          ..addAll(parsed);
        _fetchedAt = DateTime.now();
      }
      onProgress?.call(1, 1);
      return parsed.length;
    } catch (_) {
      _down = true;
      onProgress?.call(1, 1);
      return 0;
    }
  }

  /// 解析 XMLTV，返回 pid -> 当天节目单（按开始时间排序、同开始时间去重）。
  static Map<String, List<EpgProgram>> parse(String xml, DateTime day) {
    // channel id -> pid（反查，避免每条都遍历映射表）
    final pidByChannel = <String, String>{};
    XmltvChannels.ids.forEach((pid, ch) => pidByChannel[ch] = pid);

    final out = <String, List<EpgProgram>>{};
    for (final m in _progRe.allMatches(xml)) {
      final attrs = m.group(1) ?? '';
      final channel = _attrChannelRe.firstMatch(attrs)?.group(1);
      if (channel == null) continue;
      final pid = pidByChannel[channel];
      if (pid == null) continue;
      final startStr = _attrStartRe.firstMatch(attrs)?.group(1);
      if (startStr == null) continue;
      final start = _parseTs(startStr);
      if (start == null ||
          start.year != day.year ||
          start.month != day.month ||
          start.day != day.day) {
        continue;
      }
      final title = _decode(_titleRe.firstMatch(m.group(2) ?? '')?.group(1) ?? '')
          .trim();
      if (title.isEmpty) continue;
      final stopStr = _attrStopRe.firstMatch(attrs)?.group(1);
      final stop = stopStr != null ? _parseTs(stopStr) : null;
      final end = (stop != null && stop.isAfter(start))
          ? stop
          : start.add(const Duration(minutes: 30));
      out.putIfAbsent(pid, () => []).add(EpgProgram(
            id: '$pid-$startStr',
            channelId: pid,
            title: title,
            startTime: start,
            endTime: end,
          ));
    }

    // 排序 + 同一开始时间只保留第一条
    out.forEach((pid, list) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
      final seen = <DateTime>{};
      list.retainWhere((p) => seen.add(p.startTime));
    });
    out.removeWhere((_, list) => list.isEmpty);
    return out;
  }

  /// XMLTV 时间形如 `20261025120100`（本地时间，带 +0800 时区）。
  /// 本应用面向国内电视用户，直接按本地墙钟时间构造即可。
  static DateTime? _parseTs(String s) {
    if (s.length != 14) return null;
    final y = int.tryParse(s.substring(0, 4));
    final mo = int.tryParse(s.substring(4, 6));
    final d = int.tryParse(s.substring(6, 8));
    final h = int.tryParse(s.substring(8, 10));
    final mi = int.tryParse(s.substring(10, 12));
    final se = int.tryParse(s.substring(12, 14));
    if (y == null || mo == null || d == null || h == null || mi == null) {
      return null;
    }
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null;
    return DateTime(y, mo, d, h, mi, se ?? 0);
  }

  /// 实体解码。源站部分标题存在二次转义（`&amp;lt;`），因此最多解码两遍。
  static String _decode(String s) {
    var v = s;
    for (var i = 0; i < 2; i++) {
      final before = v;
      v = v
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&#39;', "'")
          .replaceAll('&nbsp;', ' ');
      if (v == before) break;
    }
    return v;
  }

  void dispose() {
    _client.close();
  }
}
