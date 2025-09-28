import 'package:hive/hive.dart';
import 'package:pilipala/models/sponsor_block/segment.dart';
import 'package:pilipala/utils/storage.dart';
import 'init.dart';

/// BilibiliSponsorBlock API 服务
///
/// 提供与 BilibiliSponsorBlock 服务器通信的功能
class SponsorBlockHttp {
  /// BSB API 基础URL
  static const String _baseUrl = 'https://bsb-service.jjj8.top';

  /// 备用API服务器列表
  static const List<String> _fallbackUrls = [
    'https://bsbsb.top',
    'https://sponsorblock.jjj8.top',
  ];

  /// 获取设置存储实例（动态获取以避免初始化时序问题）
  static Box get setting => GStrorage.setting;

  /// 获取视频的SponsorBlock数据
  ///
  /// [videoId] 视频的bvid
  /// [categories] 需要获取的片段类别，默认获取所有
  static Future<Map<String, dynamic>> getSkipSegments({
    required String videoId,
    List<String>? categories,
  }) async {
    try {
      // 构建请求参数
      final Map<String, dynamic> params = {
        'videoID': videoId,
        'categories': _buildCategoriesParam(categories),
      };

      final response = await _makeRequest('/api/skipSegments', params);

      if (response != null && response is List) {
        final segments = SponsorBlockResponse.fromJson(response, videoId);
        return {
          'status': true,
          'data': segments,
          'segments': response,
        };
      }

      return {
        'status': true,
        'data': SponsorBlockResponse(
          segments: [],
          videoId: videoId,
          videoDuration: 0,
        ),
        'segments': [],
      };
    } catch (error) {
      print('SponsorBlock API error: $error');
      return {
        'status': false,
        'data': null,
        'error': error.toString(),
        'msg': '获取SponsorBlock数据失败: $error',
      };
    }
  }

  /// 提交新的片段数据
  ///
  /// [videoId] 视频bvid
  /// [startTime] 开始时间（秒）
  /// [endTime] 结束时间（秒）
  /// [category] 片段类别
  /// [description] 可选的描述
  static Future<Map<String, dynamic>> submitSegment({
    required String videoId,
    required double startTime,
    required double endTime,
    required SponsorSegmentCategory category,
    String? description,
  }) async {
    try {
      if (!_isUserIdConfigured()) {
        return {
          'status': false,
          'msg': '请先在设置中配置用户ID',
        };
      }

      final Map<String, dynamic> data = {
        'videoID': videoId,
        'userID': _getUserId(),
        'segments': [
          {
            'segment': [startTime, endTime],
            'category': category.value,
            'actionType': 'skip',
            'description': description,
          }
        ],
      };

      final response =
          await _makeRequest('/api/postSkipSegments', data, isPost: true);

      if (response != null) {
        return {
          'status': true,
          'data': response,
          'msg': '片段提交成功',
        };
      }

      return {
        'status': false,
        'msg': '提交失败，请稍后重试',
      };
    } catch (error) {
      return {
        'status': false,
        'msg': '提交失败: $error',
      };
    }
  }

  /// 对片段进行投票
  ///
  /// [uuid] 片段UUID
  /// [type] 投票类型：0=否决，1=支持，20=撤回投票
  static Future<Map<String, dynamic>> voteOnSegment({
    required String uuid,
    required int type, // 0: downvote, 1: upvote, 20: undo
  }) async {
    try {
      if (!_isUserIdConfigured()) {
        return {
          'status': false,
          'msg': '请先在设置中配置用户ID',
        };
      }

      final Map<String, dynamic> data = {
        'userID': _getUserId(),
        'UUID': uuid,
        'type': type,
      };

      final response =
          await _makeRequest('/api/voteOnSponsorTime', data, isPost: true);

      return {
        'status': true,
        'data': response,
        'msg': type == 1
            ? '投票支持成功'
            : type == 0
                ? '投票否决成功'
                : '撤回投票成功',
      };
    } catch (error) {
      return {
        'status': false,
        'msg': '投票失败: $error',
      };
    }
  }

  /// 获取用户统计信息
  static Future<Map<String, dynamic>> getUserStats() async {
    try {
      if (!_isUserIdConfigured()) {
        return {'status': false, 'msg': '请先配置用户ID'};
      }

      final params = {'userID': _getUserId()};
      final response = await _makeRequest('/api/userInfo', params);

      return {
        'status': true,
        'data': response,
      };
    } catch (error) {
      return {
        'status': false,
        'msg': '获取用户统计失败: $error',
      };
    }
  }

  /// 获取视频详细信息（包括总节省时间）
  static Future<Map<String, dynamic>> getVideoInfo(String videoId) async {
    try {
      final params = {'videoID': videoId};
      final response = await _makeRequest('/api/videoInfo', params);

      return {
        'status': true,
        'data': response,
      };
    } catch (error) {
      return {
        'status': false,
        'msg': '获取视频信息失败: $error',
      };
    }
  }

  /// 执行API请求（支持多服务器fallback）
  static Future<dynamic> _makeRequest(
    String endpoint,
    Map<String, dynamic> params, {
    bool isPost = false,
  }) async {
    final urls = [_baseUrl, ..._fallbackUrls];

    for (String baseUrl in urls) {
      try {
        final response = isPost
            ? await Request().post('$baseUrl$endpoint', data: params)
            : await Request().get('$baseUrl$endpoint', data: params);

        if (response.statusCode == 200) {
          return response.data;
        }
      } catch (error) {
        print('Request failed for $baseUrl: $error');
        continue; // 尝试下一个服务器
      }
    }

    throw Exception('所有SponsorBlock服务器都无法访问');
  }

  /// 构建分类参数
  static String _buildCategoriesParam(List<String>? categories) {
    if (categories == null || categories.isEmpty) {
      // 默认获取的分类
      return '["sponsor","selfpromo","interaction","intro","outro","preview","music_offtopic","filler"]';
    }
    return '[${categories.map((c) => '"$c"').join(',')}]';
  }

  /// 检查用户ID是否已配置
  static bool _isUserIdConfigured() {
    final userId = setting.get(SettingBoxKey.sponsorBlockUserId);
    return userId != null && userId.isNotEmpty;
  }

  /// 获取用户ID
  static String _getUserId() {
    return setting.get(SettingBoxKey.sponsorBlockUserId, defaultValue: '');
  }

  /// 生成新的用户ID
  static String generateUserId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    String result = '';

    var value = random;
    for (int i = 0; i < 32; i++) {
      result += chars[value % chars.length];
      value = value ~/ chars.length + (i * 17); // 添加一些变化
    }

    return result;
  }

  /// 初始化用户ID（如果未设置）
  static void initializeUserId() {
    if (!_isUserIdConfigured()) {
      final newUserId = generateUserId();
      setting.put(SettingBoxKey.sponsorBlockUserId, newUserId);
    }
  }
}
