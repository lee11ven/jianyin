import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 端侧保活桥：把「Home 会话期间保持采集与连接」交给平台能力。
///
/// - Android：启动/停止前台服务（`FOREGROUND_SERVICE_CAMERA`）；
/// - iOS：无需服务；保活由 `UIBackgroundModes = [audio]` + 播放会话
///   `AVAudioSessionCategoryPlayback` 提供（见 PcmPlayerPlugin）。
///
/// 无原生实现（桌面 / 未实现的平台）时安全降级为 no-op，不阻断会话。
class KeepAliveChannel {
  KeepAliveChannel({MethodChannel? channel, this.enabled = true})
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'jianyin/keepalive';

  final MethodChannel _channel;

  /// 是否启用（测试可关掉）。
  final bool enabled;

  bool _active = false;

  bool get active => _active;

  /// 进入 Home 且会话建立后调用。
  Future<bool> start() async {
    if (!enabled) return false;
    if (_active) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('start') ?? false;
      _active = ok;
      return ok;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('keep-alive start failed: ${e.message}');
      return false;
    }
  }

  /// 离开 Home / 退出应用 / 会话结束：停止保活并清掉常驻通知。
  Future<void> stop() async {
    if (!enabled) return;
    if (!_active) return;
    _active = false;
    try {
      await _channel.invokeMethod<bool>('stop');
    } on MissingPluginException {
      /* 无原生实现：忽略 */
    } on PlatformException catch (e) {
      debugPrint('keep-alive stop failed: ${e.message}');
    }
  }
}