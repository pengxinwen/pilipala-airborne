import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/sponsor_block.dart';
import 'package:pilipala/models/sponsor_block/segment.dart';
import 'package:pilipala/services/sponsor_block_service.dart';
import 'package:pilipala/utils/storage.dart';

/// SponsorBlock 设置页面
class SponsorBlockSettingPage extends StatefulWidget {
  const SponsorBlockSettingPage({Key? key}) : super(key: key);

  @override
  State<SponsorBlockSettingPage> createState() => _SponsorBlockSettingPageState();
}

class _SponsorBlockSettingPageState extends State<SponsorBlockSettingPage> {
  /// 获取设置存储实例（动态获取以避免初始化时序问题）
  Box get setting => GStrorage.setting;
  
  bool _isEnabled = false;
  bool _isAutoSkip = true;
  bool _showToast = true;
  bool _showAnimation = true;
  String _userId = '';
  List<String> _enabledCategories = [];
  Map<String, dynamic>? _userStats;
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUserStats();
  }

  void _loadSettings() {
    _isEnabled = setting.get(SettingBoxKey.enableSponsorBlock, defaultValue: false);
    _isAutoSkip = setting.get(SettingBoxKey.sponsorBlockAutoSkip, defaultValue: true);
    _showToast = setting.get(SettingBoxKey.sponsorBlockShowToast, defaultValue: true);
    _showAnimation = setting.get(SettingBoxKey.sponsorBlockSkipAnimation, defaultValue: true);
    _userId = setting.get(SettingBoxKey.sponsorBlockUserId, defaultValue: '');
    _enabledCategories = setting.get(
      SettingBoxKey.sponsorBlockCategories,
      defaultValue: ['sponsor', 'selfpromo', 'interaction'],
    ).cast<String>();

    // 如果没有用户ID，生成一个
    if (_userId.isEmpty) {
      _generateNewUserId();
    }
  }

  void _loadUserStats() async {
    setState(() {
      _isLoadingStats = true;
    });

    try {
      final response = await SponsorBlockHttp.getUserStats();
      if (response['status']) {
        setState(() {
          _userStats = response['data'];
        });
      }
    } catch (e) {
      print('Failed to load user stats: $e');
    } finally {
      setState(() {
        _isLoadingStats = false;
      });
    }
  }

  void _generateNewUserId() {
    final newUserId = SponsorBlockHttp.generateUserId();
    setState(() {
      _userId = newUserId;
    });
    setting.put(SettingBoxKey.sponsorBlockUserId, newUserId);
  }

  void _toggleEnabled(bool value) {
    setState(() {
      _isEnabled = value;
    });
    setting.put(SettingBoxKey.enableSponsorBlock, value);
    SponsorBlockService.instance.toggleEnabled(value);
  }

  void _updateSetting(String key, bool value) {
    setState(() {
      switch (key) {
        case 'autoSkip':
          _isAutoSkip = value;
          setting.put(SettingBoxKey.sponsorBlockAutoSkip, value);
          break;
        case 'showToast':
          _showToast = value;
          setting.put(SettingBoxKey.sponsorBlockShowToast, value);
          break;
        case 'showAnimation':
          _showAnimation = value;
          setting.put(SettingBoxKey.sponsorBlockSkipAnimation, value);
          break;
      }
    });
  }

  void _updateCategories(String category, bool enabled) {
    setState(() {
      if (enabled) {
        _enabledCategories.add(category);
      } else {
        _enabledCategories.remove(category);
      }
    });
    setting.put(SettingBoxKey.sponsorBlockCategories, _enabledCategories);
    SponsorBlockService.instance.updateEnabledCategories(_enabledCategories);
  }

  void _showUserIdDialog() {
    final controller = TextEditingController(text: _userId);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用户ID设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '用户ID用于标识您的SponsorBlock贡献。通常无需修改。',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '用户ID',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _userId = controller.text;
              });
              setting.put(SettingBoxKey.sponsorBlockUserId, controller.text);
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
          TextButton(
            onPressed: () {
              _generateNewUserId();
              Navigator.of(context).pop();
            },
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    if (_isLoadingStats) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('加载统计数据中...'),
            ],
          ),
        ),
      );
    }

    if (_userStats == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.analytics_outlined),
                  SizedBox(width: 8),
                  Text('用户统计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('无法获取统计数据'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loadUserStats,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined),
                SizedBox(width: 8),
                Text('用户统计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatItem('已提交片段', '${_userStats!['segmentCount'] ?? 0}'),
            _buildStatItem('总节省时间', '${_userStats!['viewCount'] ?? 0} 次观看'),
            _buildStatItem('获得票数', '${_userStats!['totalVotes'] ?? 0}'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadUserStats,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新统计'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(SponsorSegmentCategory category) {
    final isEnabled = _enabledCategories.contains(category.value);
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isEnabled ? Colors.green : Colors.grey,
        child: Text(
          category.icon,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(category.displayName),
      subtitle: Text(_getCategoryDescription(category)),
      trailing: Switch(
        value: isEnabled,
        onChanged: (value) => _updateCategories(category.value, value),
      ),
    );
  }

  String _getCategoryDescription(SponsorSegmentCategory category) {
    switch (category) {
      case SponsorSegmentCategory.sponsor:
        return '付费推广、赞助商内容';
      case SponsorSegmentCategory.selfpromo:
        return '自我推广、频道宣传';
      case SponsorSegmentCategory.interaction:
        return '一键三连、关注提醒';
      case SponsorSegmentCategory.intro:
        return '开场动画、片头';
      case SponsorSegmentCategory.outro:
        return '结尾致谢、片尾';
      case SponsorSegmentCategory.preview:
        return '预告、剧透内容';
      case SponsorSegmentCategory.music_offtopic:
        return '无关音乐片段';
      case SponsorSegmentCategory.filler:
        return '填充内容、无意义片段';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.block),
            SizedBox(width: 8),
            Text('SponsorBlock'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 功能开关
          Card(
            child: SwitchListTile(
              title: const Text('启用 SponsorBlock'),
              subtitle: const Text('自动跳过视频中的广告片段'),
              value: _isEnabled,
              onChanged: _toggleEnabled,
            ),
          ),
          
          if (_isEnabled) ...[
            const SizedBox(height: 16),
            
            // 基础设置
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('自动跳过'),
                    subtitle: const Text('检测到片段时自动跳过'),
                    value: _isAutoSkip,
                    onChanged: (value) => _updateSetting('autoSkip', value),
                  ),
                  SwitchListTile(
                    title: const Text('显示提示'),
                    subtitle: const Text('跳过时显示Toast提示'),
                    value: _showToast,
                    onChanged: (value) => _updateSetting('showToast', value),
                  ),
                  SwitchListTile(
                    title: const Text('跳过动画'),
                    subtitle: const Text('启用跳过动画效果'),
                    value: _showAnimation,
                    onChanged: (value) => _updateSetting('showAnimation', value),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 用户设置
            Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: const Text('用户ID'),
                subtitle: Text(_userId.length > 20 ? '${_userId.substring(0, 20)}...' : _userId),
                trailing: const Icon(Icons.edit),
                onTap: _showUserIdDialog,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 用户统计
            _buildStatsCard(),
            
            const SizedBox(height: 16),
            
            // 片段类别设置
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.category),
                        SizedBox(width: 8),
                        Text('片段类别', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  ...SponsorSegmentCategory.values
                      .where((category) => category != SponsorSegmentCategory.poi_highlight)
                      .map((category) => _buildCategoryTile(category))
                      .toList(),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 说明信息
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text('关于 SponsorBlock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SponsorBlock 是一个由社区驱动的项目，旨在跳过YouTube和哔哩哔哩视频中的赞助内容。所有片段数据都由用户贡献。',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            // TODO: 打开官网
                          },
                          icon: const Icon(Icons.web, size: 16),
                          label: const Text('官网'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            // TODO: 查看API文档
                          },
                          icon: const Icon(Icons.description, size: 16),
                          label: const Text('API文档'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
