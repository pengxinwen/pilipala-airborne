/// BilibiliSponsorBlock 片段数据模型
/// 
/// 用于表示视频中需要跳过的片段信息
class SponsorSegment {
  /// 片段唯一标识
  final String uuid;
  
  /// 视频ID (bvid)
  final String videoId;
  
  /// 开始时间 (秒)
  final double startTime;
  
  /// 结束时间 (秒)
  final double endTime;
  
  /// 片段类型
  final SponsorSegmentCategory category;
  
  /// 操作类型
  final SponsorSegmentAction action;
  
  /// 创建时间
  final DateTime timeSubmitted;
  
  /// 用户投票数
  final int votes;
  
  /// 片段描述
  final String? description;

  const SponsorSegment({
    required this.uuid,
    required this.videoId,
    required this.startTime,
    required this.endTime,
    required this.category,
    required this.action,
    required this.timeSubmitted,
    required this.votes,
    this.description,
  });

  /// 从JSON创建实例
  factory SponsorSegment.fromJson(Map<String, dynamic> json) {
    return SponsorSegment(
      uuid: json['UUID'] ?? '',
      videoId: json['videoID'] ?? '',
      startTime: (json['segment'][0] as num).toDouble(),
      endTime: (json['segment'][1] as num).toDouble(),
      category: SponsorSegmentCategoryExt.fromString(json['category']),
      action: SponsorSegmentActionExt.fromString(json['actionType']),
      timeSubmitted: DateTime.fromMillisecondsSinceEpoch(
        (json['timeSubmitted'] as num).toInt() * 1000,
      ),
      votes: json['votes'] ?? 0,
      description: json['description'],
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'UUID': uuid,
      'videoID': videoId,
      'segment': [startTime, endTime],
      'category': category.value,
      'actionType': action.value,
      'timeSubmitted': timeSubmitted.millisecondsSinceEpoch ~/ 1000,
      'votes': votes,
      'description': description,
    };
  }

  /// 检查当前时间是否在此片段内
  bool contains(double currentTime) {
    return currentTime >= startTime && currentTime <= endTime;
  }

  /// 获取片段时长
  double get duration => endTime - startTime;

  /// 是否为自动跳过片段
  bool get isAutoSkip => action == SponsorSegmentAction.skip;

  @override
  String toString() {
    return 'SponsorSegment(uuid: $uuid, category: ${category.displayName}, '
           'time: ${startTime.toStringAsFixed(1)}s-${endTime.toStringAsFixed(1)}s)';
  }
}

/// 片段类别
enum SponsorSegmentCategory {
  /// 赞助广告
  sponsor('sponsor', '恰饭', '⚡'),
  
  /// 无关内容
  selfpromo('selfpromo', '自我推广', '💡'),
  
  /// 无声/音乐片段
  music_offtopic('music_offtopic', '无关音乐', '🎵'),
  
  /// 开场动画
  intro('intro', '开场', '📺'),
  
  /// 结尾致谢
  outro('outro', '结尾', '📝'),
  
  /// 预告/剧透
  preview('preview', '预告', '⏭️'),
  
  /// 一键三连提醒
  interaction('interaction', '互动提醒', '👆'),
  
  /// 高潮部分（不跳过，仅显示）
  poi_highlight('poi_highlight', '精彩时刻', '⭐'),
  
  /// 填充内容
  filler('filler', '填充内容', '⏸️');

  const SponsorSegmentCategory(this.value, this.displayName, this.icon);
  
  final String value;
  final String displayName;
  final String icon;
}

extension SponsorSegmentCategoryExt on SponsorSegmentCategory {
  static SponsorSegmentCategory fromString(String value) {
    return SponsorSegmentCategory.values.firstWhere(
      (category) => category.value == value,
      orElse: () => SponsorSegmentCategory.sponsor,
    );
  }
}

/// 片段操作类型
enum SponsorSegmentAction {
  /// 跳过
  skip('skip'),
  
  /// 静音
  mute('mute'),
  
  /// 仅显示（不执行操作）
  full('full'),
  
  /// 空操作
  poi('poi');

  const SponsorSegmentAction(this.value);
  final String value;
}

extension SponsorSegmentActionExt on SponsorSegmentAction {
  static SponsorSegmentAction fromString(String value) {
    return SponsorSegmentAction.values.firstWhere(
      (action) => action.value == value,
      orElse: () => SponsorSegmentAction.skip,
    );
  }
}

/// BilibiliSponsorBlock API响应模型
class SponsorBlockResponse {
  final List<SponsorSegment> segments;
  final String videoId;
  final int videoDuration;

  const SponsorBlockResponse({
    required this.segments,
    required this.videoId,
    required this.videoDuration,
  });

  factory SponsorBlockResponse.fromJson(List<dynamic> json, String videoId) {
    final segments = json
        .map((item) => SponsorSegment.fromJson(item as Map<String, dynamic>))
        .toList();
    
    return SponsorBlockResponse(
      segments: segments,
      videoId: videoId,
      videoDuration: 0, // 由调用方提供
    );
  }

  /// 获取在指定时间点的活动片段
  SponsorSegment? getActiveSegment(double currentTime) {
    return segments.cast<SponsorSegment?>().firstWhere(
      (segment) => segment!.contains(currentTime),
      orElse: () => null,
    );
  }

  /// 获取按类别分组的片段
  Map<SponsorSegmentCategory, List<SponsorSegment>> get segmentsByCategory {
    final Map<SponsorSegmentCategory, List<SponsorSegment>> result = {};
    for (final segment in segments) {
      result.putIfAbsent(segment.category, () => []).add(segment);
    }
    return result;
  }
}

