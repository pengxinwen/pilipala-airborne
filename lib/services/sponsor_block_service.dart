import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/sponsor_block.dart';
import 'package:pilipala/models/sponsor_block/segment.dart';
import 'package:pilipala/plugin/pl_player/controller.dart';
import 'package:pilipala/utils/storage.dart';

/// SponsorBlock 服务
/// 
/// 负责处理视频播放期间的 SponsorBlock 功能
/// 包括片段检测、自动跳过、用户交互等
class SponsorBlockService {
  static SponsorBlockService? _instance;
  static SponsorBlockService get instance => _instance ??= SponsorBlockService._internal();
  
  SponsorBlockService._internal();

  /// 获取设置存储实例（动态获取以避免初始化时序问题）
  Box get setting => GStrorage.setting;
  
  /// 当前视频的SponsorBlock数据
  SponsorBlockResponse? _currentVideoData;
  
  /// 当前播放器控制器
  PlPlayerController? _playerController;
  
  /// 位置监听器
  StreamSubscription? _positionSubscription;
  
  /// 当前活动的片段
  SponsorSegment? _currentActiveSegment;
  
  /// 已跳过的片段UUID列表（防止重复跳过）
  final Set<String> _skippedSegments = {};
  
  /// 用户手动取消的片段UUID列表
  final Set<String> _userCancelledSegments = {};
  
  /// 最后一次显示toast的时间
  DateTime? _lastToastTime;

  /// SponsorBlock功能是否启用
  bool get isEnabled => setting.get(SettingBoxKey.enableSponsorBlock, defaultValue: false);
  
  /// 是否自动跳过
  bool get isAutoSkipEnabled => setting.get(SettingBoxKey.sponsorBlockAutoSkip, defaultValue: true);
  
  /// 是否显示跳过提示
  bool get isToastEnabled => setting.get(SettingBoxKey.sponsorBlockShowToast, defaultValue: true);
  
  /// 启用的片段类别
  List<String> get enabledCategories => setting.get(
    SettingBoxKey.sponsorBlockCategories, 
    defaultValue: ['sponsor', 'selfpromo', 'interaction'],
  ).cast<String>();

  /// 初始化视频的SponsorBlock数据
  /// 
  /// [videoId] 视频bvid
  /// [playerController] 播放器控制器
  Future<void> initializeVideo({
    required String videoId,
    required PlPlayerController playerController,
  }) async {
    if (!isEnabled) {
      return;
    }

    // 清理之前的状态
    await dispose();
    
    _playerController = playerController;
    _skippedSegments.clear();
    _userCancelledSegments.clear();
    _currentActiveSegment = null;

    try {
      // 获取SponsorBlock数据
      print('Loading SponsorBlock data for video: $videoId');
      final response = await SponsorBlockHttp.getSkipSegments(
        videoId: videoId,
        categories: enabledCategories,
      );

      if (response['status'] == true) {
        _currentVideoData = response['data'] as SponsorBlockResponse;
        print('Loaded ${_currentVideoData!.segments.length} sponsor segments');
        
        // 开始监听播放位置
        _startPositionListening();
        
        // 显示加载成功的信息
        if (isToastEnabled && _currentVideoData!.segments.isNotEmpty) {
          _showToast(
            '🎯 已加载 ${_currentVideoData!.segments.length} 个SponsorBlock片段',
            duration: 2,
          );
        }
      } else {
        print('Failed to load SponsorBlock data: ${response['msg']}');
      }
    } catch (error) {
      print('SponsorBlock initialization error: $error');
    }
  }

  /// 开始监听播放位置
  void _startPositionListening() {
    if (_playerController == null) return;

    _positionSubscription = _playerController!.onPositionChanged.listen((position) {
      _checkForSponsorSegments(position.inSeconds.toDouble());
    });
  }

  /// 检查当前播放位置是否命中SponsorBlock片段
  void _checkForSponsorSegments(double currentTime) {
    if (_currentVideoData == null || _currentVideoData!.segments.isEmpty) {
      return;
    }

    // 查找当前时间点的活动片段
    final activeSegment = _currentVideoData!.getActiveSegment(currentTime);
    
    // 如果没有活动片段，清除当前状态
    if (activeSegment == null) {
      _currentActiveSegment = null;
      return;
    }

    // 如果是新的片段
    if (_currentActiveSegment?.uuid != activeSegment.uuid) {
      _currentActiveSegment = activeSegment;
      _handleSegmentDetected(activeSegment, currentTime);
    }
  }

  /// 处理检测到的片段
  void _handleSegmentDetected(SponsorSegment segment, double currentTime) {
    print('Detected sponsor segment: ${segment.category.displayName} at ${currentTime.toStringAsFixed(1)}s');

    // 检查是否已经跳过或用户取消过
    if (_skippedSegments.contains(segment.uuid) || 
        _userCancelledSegments.contains(segment.uuid)) {
      return;
    }

    // 根据片段类型和设置决定操作
    switch (segment.action) {
      case SponsorSegmentAction.skip:
        if (isAutoSkipEnabled && segment.category != SponsorSegmentCategory.poi_highlight) {
          _skipSegment(segment);
        } else {
          _showSkipPrompt(segment);
        }
        break;
      case SponsorSegmentAction.mute:
        _muteSegment(segment);
        break;
      case SponsorSegmentAction.full:
      case SponsorSegmentAction.poi:
        _showSegmentInfo(segment);
        break;
    }
  }

  /// 跳过片段
  void _skipSegment(SponsorSegment segment) {
    if (_playerController == null) return;

    _playerController!.seekTo(Duration(seconds: segment.endTime.ceil()));
    _skippedSegments.add(segment.uuid);

    // 显示跳过提示
    if (isToastEnabled) {
      final savedTime = (segment.endTime - segment.startTime).toStringAsFixed(1);
      _showToast(
        '⚡ 已跳过${segment.category.displayName} (${savedTime}s)',
        icon: segment.category.icon,
        duration: 3,
      );
    }

    // 记录统计信息
    _recordSkipStats(segment);
  }

  /// 显示手动跳过提示
  void _showSkipPrompt(SponsorSegment segment) {
    if (!isToastEnabled || _isToastCooldown()) return;

    _lastToastTime = DateTime.now();
    
    SmartDialog.show(
      alignment: Alignment.topCenter,
      builder: (context) => Container(
        margin: const EdgeInsets.only(top: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              segment.category.icon,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 8),
            Text(
              '检测到${segment.category.displayName}片段',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                _skipSegment(segment);
              },
              child: const Text('跳过', style: TextStyle(color: Colors.blue)),
            ),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                _userCancelledSegments.add(segment.uuid);
              },
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
      displayTime: const Duration(seconds: 5),
    );
  }

  /// 静音片段
  void _muteSegment(SponsorSegment segment) {
    // TODO: 实现静音功能
    _showToast(
      '🔇 ${segment.category.displayName}片段已静音',
      duration: 2,
    );
  }

  /// 显示片段信息（如精彩时刻）
  void _showSegmentInfo(SponsorSegment segment) {
    if (!isToastEnabled || _isToastCooldown()) return;

    _showToast(
      '${segment.category.icon} ${segment.category.displayName}',
      duration: 3,
    );
  }

  /// 显示Toast消息
  void _showToast(String message, {String? icon, int duration = 2}) {
    SmartDialog.showToast(
      icon != null ? '$icon $message' : message,
      displayTime: Duration(seconds: duration),
    );
  }

  /// 检查Toast冷却时间
  bool _isToastCooldown() {
    if (_lastToastTime == null) return false;
    return DateTime.now().difference(_lastToastTime!).inSeconds < 3;
  }

  /// 记录跳过统计
  void _recordSkipStats(SponsorSegment segment) {
    // TODO: 实现本地统计记录
    print('Skipped segment: ${segment.category.displayName}, '
          'duration: ${(segment.endTime - segment.startTime).toStringAsFixed(1)}s');
  }

  /// 手动跳转到指定时间（用于用户点击进度条等情况）
  void onManualSeek(double targetTime) {
    // 如果用户跳转到已跳过的片段内，移除跳过记录，允许重新检测
    if (_currentVideoData != null) {
      final targetSegment = _currentVideoData!.getActiveSegment(targetTime);
      if (targetSegment != null && _skippedSegments.contains(targetSegment.uuid)) {
        _skippedSegments.remove(targetSegment.uuid);
      }
    }
  }

  /// 获取当前视频的SponsorBlock统计信息
  Map<String, dynamic> getVideoStats() {
    if (_currentVideoData == null) {
      return {'segments': 0, 'totalDuration': 0.0};
    }

    double totalDuration = 0.0;
    final segmentsByCategory = <String, int>{};

    for (final segment in _currentVideoData!.segments) {
      totalDuration += segment.duration;
      segmentsByCategory[segment.category.displayName] = 
          (segmentsByCategory[segment.category.displayName] ?? 0) + 1;
    }

    return {
      'segments': _currentVideoData!.segments.length,
      'totalDuration': totalDuration,
      'skippedCount': _skippedSegments.length,
      'categories': segmentsByCategory,
    };
  }

  /// 提交新片段
  Future<bool> submitSegment({
    required String videoId,
    required double startTime,
    required double endTime,
    required SponsorSegmentCategory category,
    String? description,
  }) async {
    try {
      final response = await SponsorBlockHttp.submitSegment(
        videoId: videoId,
        startTime: startTime,
        endTime: endTime,
        category: category,
        description: description,
      );

      if (response['status']) {
        _showToast('✅ 片段提交成功！感谢您的贡献', duration: 3);
        
        // 重新加载当前视频的数据
        if (_playerController != null) {
          await initializeVideo(
            videoId: videoId, 
            playerController: _playerController!,
          );
        }
        
        return true;
      } else {
        _showToast('❌ 提交失败: ${response['msg']}', duration: 3);
        return false;
      }
    } catch (error) {
      _showToast('❌ 提交失败: $error', duration: 3);
      return false;
    }
  }

  /// 对片段进行投票
  Future<void> voteSegment(String uuid, bool isUpvote) async {
    try {
      final response = await SponsorBlockHttp.voteOnSegment(
        uuid: uuid,
        type: isUpvote ? 1 : 0,
      );

      if (response['status']) {
        _showToast(
          isUpvote ? '👍 投票支持成功' : '👎 投票否决成功',
          duration: 2,
        );
      } else {
        _showToast('投票失败: ${response['msg']}', duration: 2);
      }
    } catch (error) {
      _showToast('投票失败: $error', duration: 2);
    }
  }

  /// 切换SponsorBlock功能
  void toggleEnabled(bool enabled) {
    setting.put(SettingBoxKey.enableSponsorBlock, enabled);
    
    if (!enabled) {
      dispose();
    }
  }

  /// 更新启用的片段类别
  void updateEnabledCategories(List<String> categories) {
    setting.put(SettingBoxKey.sponsorBlockCategories, categories);
  }

  /// 清理资源
  Future<void> dispose() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _playerController = null;
    _currentVideoData = null;
    _currentActiveSegment = null;
    _skippedSegments.clear();
    _userCancelledSegments.clear();
  }
}
