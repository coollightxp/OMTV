import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/epg_program.dart';
import '../services/player_controller.dart';
import 'scaled_panel.dart';

/// 底部信息/控制面板
/// 布局：台标 | 当前节目(大字)+时段/频道/分辨率 | 控制按钮
/// 按钮顺序固定：播放/暂停、全屏/小窗（电视端不显示）、静音/恢复、旋转、
/// 截图/录像(桌面)、分辨率
/// （听电视/锁定/设置与安卓一致，统一放在返回键弹出的退出面板里）
///
/// 遥控器导航（TV 盒子无鼠标）：面板可见时，←/→ 在可用按钮间移动高亮，
/// OK 激活当前按钮，返回键由播放页负责关闭面板。
class BottomProgramPanel extends StatefulWidget {
  final bool isVisible;

  /// 跳转类（频道/EPG/设置）由播放页关闭面板
  final VoidCallback onOpenChannels;
  final VoidCallback onOpenEpg;
  final VoidCallback onOpenSettings;

  /// 全屏 ↔ 小窗（桌面全屏切换 / 移动端小窗播放）
  final VoidCallback onToggleFullMini;

  /// 截图 / 录像（仅桌面端提供按钮）
  final VoidCallback onScreenshot;
  final VoidCallback onToggleRecord;

  final VoidCallback? onDismissRemote;
  final VoidCallback? onHoverEnter;
  final VoidCallback? onHoverExit;
  final VoidCallback? onHoverMove;

  const BottomProgramPanel({
    super.key,
    required this.isVisible,
    required this.onOpenChannels,
    required this.onOpenEpg,
    required this.onOpenSettings,
    required this.onToggleFullMini,
    required this.onScreenshot,
    required this.onToggleRecord,
    this.onDismissRemote,
    this.onHoverEnter,
    this.onHoverExit,
    this.onHoverMove,
  });

  @override
  State<BottomProgramPanel> createState() => BottomProgramPanelState();
}

/// 面板内一个可由遥控器激活的按钮
class _KbAction {
  final String id;
  final IconData? icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 激活后是否关闭面板（跳转到其它面板/弹层 = true）
  final bool dismiss;

  const _KbAction(this.id, this.icon, this.tooltip, this.onPressed,
      {this.dismiss = false});
}

class BottomProgramPanelState extends State<BottomProgramPanel> {
  /// 遥控器当前高亮的按钮 id（null = 无高亮）
  String? _kbId;

  /// 最近一次构建出的动作列表（与按钮排列顺序一致）
  List<_KbAction> _actions = const [];

  List<_KbAction> get _enabledActions =>
      _actions.where((a) => a.onPressed != null).toList();

  @override
  void didUpdateWidget(BottomProgramPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 面板收起时顺带关掉清晰度菜单，避免下次呼出时残留
    if (!widget.isVisible && _resMenuOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _resMenuOpen) setState(() => _resMenuOpen = false);
      });
    }
    // 面板每次被呼出时，默认高亮「播放/暂停」（不可用时取第一个可用按钮）
    if (widget.isVisible && !oldWidget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final enabled = _enabledActions;
        if (enabled.isEmpty) {
          setState(() => _kbId = null);
          return;
        }
        final play = enabled.where((a) => a.id == 'playpause');
        setState(
            () => _kbId = play.isNotEmpty ? play.first.id : enabled.first.id);
      });
    }
  }

  /// 遥控器按键：←/→ 在【可用】按钮间移动高亮，OK 激活当前按钮
  void handleRemoteKey(String action, {required bool isDown}) {
    if (!widget.isVisible) return;
    // 清晰度菜单打开时：↑/↓ 选条目、OK 确认、返回关闭，不再切按钮
    if (_resMenuOpen) {
      handleResMenuKey(action, isDown: isDown);
      return;
    }
    final enabled = _enabledActions;
    if (enabled.isEmpty) return;
    if (action == 'left' || action == 'right') {
      if (!isDown) return;
      var i = enabled.indexWhere((a) => a.id == _kbId);
      setState(() {
        if (i < 0) {
          i = action == 'right' ? 0 : enabled.length - 1;
        } else if (action == 'right') {
          i = (i + 1) % enabled.length;
        } else {
          i = (i - 1 + enabled.length) % enabled.length;
        }
        _kbId = enabled[i].id;
      });
      return;
    }
    if (action == 'ok' && isDown) {
      final i = enabled.indexWhere((a) => a.id == _kbId);
      final a = i >= 0 ? enabled[i] : enabled.first;
      a.onPressed?.call();
      if (a.dismiss) widget.onDismissRemote?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final scale = panelScaleOf(context) < 1.0 ? 0.72 : 1.0;
    final hPad = screenW > 1200 ? 72.0 : (screenW > 900 ? 40.0 : 0.0);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      left: hPad,
      right: hPad,
      bottom: widget.isVisible ? (screenW > 900 ? 16 : 8) : -320,
      child: MouseRegion(
        onEnter: (_) => widget.onHoverEnter?.call(),
        onExit: (_) => widget.onHoverExit?.call(),
        onHover: (_) => widget.onHoverMove?.call(),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.isVisible ? 1.0 : 0.0,
          child: ScaledPanel(
            alignment: Alignment.bottomCenter,
            scale: 1.0,
            // 面板内空白区域也吞掉点击：移动端点面板右侧空白处时不会
            // 穿透到屏幕点击分区（右三分之一），避免误开 EPG 盖住按钮
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: scale < 1
                      ? const EdgeInsets.fromLTRB(6, 16, 4, 14)
                      : const EdgeInsets.fromLTRB(22, 16, 18, 10),
                  child: Consumer<PlayerController>(
                    builder: (context, c, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 清晰度菜单：面板内自绘，遥控器 ↑/↓ 选择、OK 确认
                        if (_resMenuOpen) _buildResMenu(c),
                        if (c.isSeekable) _buildSeekBar(c),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildLogo(c, scale),
                            SizedBox(width: scale < 1 ? 12 : 28),
                            Expanded(child: _buildInfo(c, scale)),
                            Flexible(
                              flex: 0,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: _buildButtons(c),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  // ==================== 台标 ====================

  Widget _buildLogo(PlayerController c, double scale) {
    final size = scale < 1 ? 92.0 : 128.0;
    final logo = c.currentLogo;
    Widget placeholder() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(scale < 1 ? 10 : 16),
          ),
          child: Icon(Icons.live_tv,
              color: Colors.white54, size: scale < 1 ? 46 : 64),
        );
    if (logo.isEmpty) return placeholder();
    final image = logo.startsWith('assets/')
        ? Image.asset(logo,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => placeholder())
        : Image.network(logo,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => placeholder());
    return ClipRRect(
      borderRadius: BorderRadius.circular(scale < 1 ? 10 : 16),
      child: image,
    );
  }

  // ==================== 节目信息 ====================

  String _resolutionLabel(PlayerController c) {
    final actual = c.actualResolutionLabel;
    return actual.isNotEmpty ? actual : c.resolution;
  }

  Widget _buildInfo(PlayerController c, double scale) {
    final info = c.getNowPlayingInfo();
    final current = c.currentProgram;
    final next = c.nextProgram;
    final hasChannel = c.currentChannel != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          current?.title ?? (hasChannel ? info.channelName : '未选择频道'),
          style: TextStyle(
            color: Colors.white,
            fontSize: scale < 1 ? 17 : 22,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: scale < 1 ? 3 : 5),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (current != null) _metaText(_range(current), Colors.amber),
            if (hasChannel) _metaText(info.channelName, Colors.white70),
            if (hasChannel) _badge(_resolutionLabel(c)),
            if (c.listenMode) _badge('听电视中'),
          ],
        ),
        const SizedBox(height: 3),
        if (next != null)
          Text(
            '${_range(next)}  ${next.title}',
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else if (!hasChannel)
          const Text(
            '点击屏幕或 ≡ 按钮打开频道列表',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
      ],
    );
  }

  Widget _metaText(String text, Color color) {
    return Text(text,
        style:
            TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500));
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
    );
  }

  // ==================== 点播进度条 ====================

  Widget _buildSeekBar(PlayerController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _SeekBar(controller: c, clock: _clock),
    );
  }

  // ==================== 控制按钮 ====================

  Widget _buildButtons(PlayerController c) {
    final hasChannel = c.currentChannel != null;
    final actions = <_KbAction>[
      _KbAction(
        'playpause',
        c.isPlaying ? Icons.pause : Icons.play_arrow,
        c.isPlaying ? '暂停' : '播放',
        hasChannel ? c.togglePlayPause : null,
      ),
      // 电视端没有窗口概念：画中画/小窗没有意义，直接不提供该按钮
      if (!c.isTv)
        _KbAction(
          'fullmini',
          c.isDesktop
              ? (c.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen)
              : (c.miniWindow
                  ? Icons.crop_free
                  : Icons.picture_in_picture_alt),
          c.isDesktop
              ? (c.isFullscreen ? '退出全屏' : '全屏')
              : (c.miniWindow ? '退出小窗' : '小窗播放'),
          hasChannel ? widget.onToggleFullMini : null,
        ),
      _KbAction(
        'mute',
        c.isMuted ? Icons.volume_off : Icons.volume_up,
        c.isMuted ? '取消静音' : '静音',
        hasChannel ? c.toggleMute : null,
      ),
      // 截图/录像：仅桌面端（移动端网页层无法安全截取/录制）
      if (c.isDesktop)
        _KbAction('screenshot', Icons.camera_alt, '截图',
            hasChannel ? widget.onScreenshot : null),
      if (c.isDesktop)
        _KbAction(
          'record',
          c.isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
          c.isRecording ? '停止录制' : '开始录制',
          hasChannel ? widget.onToggleRecord : null,
        ),
      // 画面旋转：90° 旋转 ↔ 恢复原始方向（遥控器/手机均可用）
      _KbAction(
        'rotate',
        Icons.screen_rotation,
        c.videoRotation.value == 0 ? '旋转画面' : '恢复原始方向',
        hasChannel ? c.cycleVideoRotation : null,
      ),
      // 听电视/锁定/设置：与安卓保持一致，统一收进返回键弹出的退出面板，
      // 底部只留播放相关按钮，避免窄窗口下图标挤压/与清晰度标签重叠
      _KbAction(
        'resolution',
        null,
        '清晰度',
        hasChannel ? () => _openResolutionMenu(c) : null,
        // 打开菜单后面板要留着（菜单在面板内），不能按 OK 就收起
        dismiss: false,
      ),
    ];
    _actions = actions;
    if (_kbId != null && !actions.any((a) => a.id == _kbId)) _kbId = null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in actions)
          if (a.id == 'resolution')
            _resolutionButton(c, a)
          else
            _btn(a, big: a.id == 'playpause'),
        // 投屏中额外提供断开入口
        if (c.isCasting)
          _wrapSelected(
            false,
            IconButton(
              icon: const Icon(Icons.cast_connected,
                  color: Colors.redAccent, size: 24),
              tooltip: '断开投屏',
              onPressed: c.stopCastAndRestore,
            ),
          ),
      ],
    );
  }

  Widget _resolutionButton(PlayerController c, _KbAction a) {
    final label = _resolutionLabel(c);
    final selected = _kbId == a.id;
    return _wrapSelected(
      selected,
      InkWell(
        onTap: a.onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: a.onPressed == null ? Colors.white24 : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_up,
                  color: a.onPressed == null ? Colors.white24 : Colors.white70,
                  size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 分辨率菜单 ====================
  // 不再用 showMenu：路由弹层收不到遥控器的 ↑/↓/OK（这些键在播放页
  // 统一分发，弹层是独立路由拿不到），改为面板内自绘菜单，
  // 由 handleResMenuKey 处理遥控器导航

  static const List<String> _resOptions = ['1080P', '720P', '540P'];
  static const Map<String, String> _resTitles = {
    '1080P': '1080P 高清',
    '720P': '720P 准高清',
    '540P': '540P 标清',
  };

  bool _resMenuOpen = false;
  int _resIndex = 0;

  void _openResolutionMenu(PlayerController c) {
    setState(() {
      if (_resMenuOpen) {
        _resMenuOpen = false;
        return;
      }
      _resMenuOpen = true;
      final i = _resOptions.indexOf(c.resolution);
      _resIndex = i < 0 ? 0 : i;
    });
  }

  Future<void> _applyResolution(String level) async {
    setState(() => _resMenuOpen = false);
    await context.read<PlayerController>().setResolution(level);
  }

  /// 遥控器/键盘在分辨率菜单内的导航；菜单未打开时返回 false 表示未消费
  bool handleResMenuKey(String action, {required bool isDown}) {
    if (!_resMenuOpen) return false;
    if (!isDown) return true;
    switch (action) {
      case 'up':
        setState(() => _resIndex =
            (_resIndex - 1 + _resOptions.length) % _resOptions.length);
        return true;
      case 'down':
        setState(
            () => _resIndex = (_resIndex + 1) % _resOptions.length);
        return true;
      case 'ok':
        _applyResolution(_resOptions[_resIndex]);
        return true;
      case 'back':
      case 'esc':
        setState(() => _resMenuOpen = false);
        return true;
    }
    return true;
  }

  /// 供播放页在返回键时调用：菜单打开则只关菜单
  bool closeResMenu() {
    if (!_resMenuOpen) return false;
    setState(() => _resMenuOpen = false);
    return true;
  }

  Widget _buildResMenu(PlayerController c) {
    final current = c.resolution;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 4),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _resOptions.length; i++)
              InkWell(
                onTap: () => _applyResolution(_resOptions[i]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: i == _resIndex
                        ? Colors.amber.withOpacity(0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        child: _resOptions[i] == current
                            ? const Icon(Icons.check,
                                color: Colors.amber, size: 16)
                            : null,
                      ),
                      Text(
                        _resTitles[_resOptions[i]] ?? _resOptions[i],
                        style: TextStyle(
                          color: i == _resIndex
                              ? Colors.white
                              : Colors.white70,
                          fontSize: 14,
                          fontWeight: i == _resIndex
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _btn(_KbAction a, {bool big = false}) {
    final selected = a.id == _kbId;
    final iconSize = big ? 30.0 : 24.0;
    // 录制中的按钮红色常亮，提示正在录制
    if (a.id == 'record' && context.read<PlayerController>().isRecording) {
      return _wrapSelected(
        selected,
        IconButton(
          icon: Icon(a.icon, color: Colors.redAccent, size: iconSize),
          onPressed: a.onPressed,
          tooltip: a.tooltip,
        ),
      );
    }
    // 旋转按钮的颜色随旋转状态变化（0=原始方向灰白，90° 高亮琥珀色）
    if (a.id == 'rotate') {
      return _wrapSelected(
        selected,
        ValueListenableBuilder<int>(
          valueListenable: context.read<PlayerController>().videoRotation,
          builder: (context, rot, _) => IconButton(
            icon: Icon(Icons.screen_rotation,
                color: a.onPressed == null
                    ? Colors.white24
                    : (rot == 0 ? Colors.white54 : Colors.amber),
                size: iconSize),
            onPressed: a.onPressed,
            tooltip: a.tooltip,
          ),
        ),
      );
    }
    final iconColor = a.id == 'listen' && context.read<PlayerController>().listenMode
        ? Colors.amber
        : (a.id == 'lock' && context.read<PlayerController>().locked
            ? Colors.amber
            : (a.onPressed == null ? Colors.white24 : Colors.white));
    return _wrapSelected(
      selected,
      IconButton(
        icon: Icon(a.icon, color: iconColor, size: iconSize),
        onPressed: a.onPressed,
        tooltip: a.tooltip,
      ),
    );
  }

  /// 遥控器高亮：蓝底圆角方框
  Widget _wrapSelected(bool selected, Widget child) {
    if (!selected) return child;
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent, width: 1.6),
      ),
      child: child,
    );
  }

  static final _hm = DateFormat('HH:mm');

  String _range(EpgProgram p) =>
      '${_hm.format(p.startTime)} - ${_hm.format(p.endTime)}';
  String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// 点播进度条。
/// 拖动过程中只更新本地预览位置，松手时才真正 seek（避免频繁打断缓冲）。
class _SeekBar extends StatefulWidget {
  final PlayerController controller;
  final String Function(Duration) clock;

  const _SeekBar({required this.controller, required this.clock});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final total = c.duration;
    final max = total.inMilliseconds.toDouble();
    final safeMax = max <= 0 ? 1.0 : max;
    final pos =
        _dragMs ?? c.position.inMilliseconds.clamp(0, safeMax.round()).toDouble();
    final value = pos.clamp(0, safeMax).toDouble();
    return Row(
      children: [
        Text(widget.clock(Duration(milliseconds: value.round())),
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.blueAccent,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.blueAccent,
            ),
            child: Slider(
              value: value,
              max: safeMax,
              onChangeStart: (v) => setState(() => _dragMs = v),
              onChanged: (v) => setState(() => _dragMs = v),
              onChangeEnd: (v) {
                c.seekTo(Duration(milliseconds: v.round()));
                setState(() => _dragMs = null);
              },
            ),
          ),
        ),
        Text(widget.clock(total),
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
