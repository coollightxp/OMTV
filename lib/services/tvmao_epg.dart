import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/tvmao_channels.dart';
import '../models/epg_program.dart';

/// 电视猫 EPG（主源）。
///
/// 电视猫频道页的节目单是服务端直出的 HTML，按天分布在
/// `https://www.tvmao.com/program/<GROUP>-<SLUG>-w<N>.html`
/// （N = 1..7 对应本周周一..周日），解析 `<span class="am/pm">HH:MM</span>`
/// 与 `<a title="节目名">` 即可拿到当天节目表。
///
/// 相比央视频接口，电视猫的节目名与实际播出更对得上，因此作为主源；
/// 抓取失败或整源不可用时由调用方回退到央视频。
class TvmaoEpg {
  /// 电视猫节目单当天基本固定，30 分钟静默刷新一次即可
  /// （跨天时 [_stale] 会强制重抓）。
  static const Duration refreshInterval = Duration(minutes: 30);
  static const String _base = 'https://www.tvmao.com/program/';

  final http.Client _client;

  /// pid -> 当天节目单（已按开始时间排序）
  final Map<String, List<EpgProgram>> _byPid = {};
  final Map<String, DateTime> _fetchedAt = {};

  /// 本次运行中是否已判定整源不可用（一旦置位不再重试）
  bool _down = false;

  TvmaoEpg({http.Client? client}) : _client = client ?? http.Client();

  List<EpgProgram> programsFor(String pid) => _byPid[pid] ?? const [];

  /// 该频道是否已有电视猫节目单
  bool has(String pid) => _byPid[pid]?.isNotEmpty ?? false;

  bool get isDown => _down;

  bool get isEmpty => _byPid.isEmpty;

  /// 网络恢复后允许重新探测整源（仅用于启动时无网导致的误判）
  void resetDown() {
    _down = false;
  }

  /// 跨天（节目单每天不同）或超过刷新间隔则需要重抓
  bool _stale(String pid) {
    final at = _fetchedAt[pid];
    if (at == null) return true;
    final now = DateTime.now();
    if (at.year != now.year || at.month != now.month || at.day != now.day) {
      return true;
    }
    return now.difference(at) > refreshInterval;
  }

  /// 批量拉取（只处理映射表里有的频道，限制并发避免打满连接）。
  /// 返回当前拥有电视猫数据、且本次请求过的频道数量；
  /// 若一个都没成功则标记整源不可用。
  Future<int> refresh(
    List<String> pids, {
    int concurrency = 6,
    bool force = false,
    void Function(int done, int total)? onProgress,
  }) async {
    if (_down) return 0;
    final targets = pids
        .where((p) => TvmaoChannels.pathFor(p) != null)
        .where((p) => force || _stale(p))
        .toList();
    if (targets.isEmpty) {
      return pids.where(has).length;
    }
    var next = 0;
    var done = 0;
    var ok = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= targets.length) return;
        try {
          if (await _fetchOne(targets[i])) ok++;
        } catch (_) {
          // 单个频道失败不影响其它频道
        }
        done++;
        onProgress?.call(done, targets.length);
      }
    }

    final workers =
        targets.length < concurrency ? targets.length : concurrency;
    await Future.wait(List.generate(workers, (_) => worker()));

    // 有目标但一个都没拿到 → 判定电视猫整体不可用，本会话不再尝试
    if (ok == 0) _down = true;
    return pids.where(has).length;
  }

  Future<bool> _fetchOne(String pid) async {
    final path = TvmaoChannels.pathFor(pid);
    if (path == null) return false;
    // 电视猫 w1..w7 与 DateTime.weekday（周一=1 … 周日=7）一致
    final weekday = DateTime.now().weekday;
    final resp = await _client
        .get(
          Uri.parse('$_base$path-w$weekday.html'),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
            'Referer': 'https://www.tvmao.com/',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return false;
    final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (!html.contains('<title>')) return false;
    final programs = parse(pid, html, DateTime.now());
    if (programs.isEmpty) return false;
    _byPid[pid] = programs;
    _fetchedAt[pid] = DateTime.now();
    return true;
  }

  static final RegExp _entryRe = RegExp(
    r'<span class="(?:a|p)m">\s*(\d{1,2}):(\d{2})\s*</span>\s*'
    r'<span class="p_show">([\s\S]*?)</span>',
  );
  static final RegExp _anchorTitleRe = RegExp(r'<a[^>]*title="([^"]*)"');
  static final RegExp _tagRe = RegExp(r'<[^>]*>');

  /// 从频道页 HTML 解析当天节目表。
  /// 结束时间取下一个节目的开始时间，最后一个节目到 24:00。
  static List<EpgProgram> parse(String pid, String html, DateTime day) {
    final starts = <({int minute, String title})>[];
    for (final m in _entryRe.allMatches(html)) {
      final h = int.tryParse(m.group(1) ?? '');
      final mi = int.tryParse(m.group(2) ?? '');
      // 节目名有两种形态：<a title="X"> 锚点，或「前缀 + 锚点」/纯文本。
      // 优先取锚点 title，取不到再剥掉标签取纯文本。
      final inner = m.group(3) ?? '';
      final anchor = _anchorTitleRe.firstMatch(inner);
      final title = _decodeEntities(
        anchor != null ? anchor.group(1) ?? '' : inner.replaceAll(_tagRe, ''),
      ).trim();
      if (h == null || mi == null || title.isEmpty) continue;
      if (h > 23 || mi > 59) continue;
      starts.add((minute: h * 60 + mi, title: title));
    }
    // 少于两条无法构成时间区间，视为无效数据（回退央视频）
    if (starts.length < 2) return const [];

    // 同一时间重复出现的条目只保留第一条
    final seen = <int>{};
    final uniq = <({int minute, String title})>[];
    for (final s in starts) {
      if (seen.add(s.minute)) uniq.add(s);
    }

    final base = DateTime(day.year, day.month, day.day);
    final out = <EpgProgram>[];
    for (var i = 0; i < uniq.length; i++) {
      // 时间回退说明已进入次日区块，停止解析当天节目单
      if (i > 0 && uniq[i].minute < uniq[i - 1].minute) break;
      final start = base.add(Duration(minutes: uniq[i].minute));
      final endMin = i + 1 < uniq.length ? uniq[i + 1].minute : 24 * 60;
      var end = base.add(Duration(minutes: endMin));
      if (!end.isAfter(start)) end = start.add(const Duration(minutes: 30));
      out.add(EpgProgram(
        id: '$pid-$endMin-${uniq[i].minute}',
        channelId: pid,
        title: uniq[i].title,
        startTime: start,
        endTime: end,
      ));
    }
    return out;
  }

  static String _decodeEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }

  void dispose() {
    _client.close();
  }
}
