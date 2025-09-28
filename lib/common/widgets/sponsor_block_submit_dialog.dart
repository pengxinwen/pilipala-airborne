import 'package:flutter/material.dart';
import 'package:pilipala/models/sponsor_block/segment.dart';

/// SponsorBlock 片段提交对话框
class SponsorBlockSubmitDialog extends StatefulWidget {
  final String videoId;
  final double currentTime;
  final Function(double startTime, double endTime, SponsorSegmentCategory category, String? description) onSubmit;

  const SponsorBlockSubmitDialog({
    Key? key,
    required this.videoId,
    required this.currentTime,
    required this.onSubmit,
  }) : super(key: key);

  @override
  State<SponsorBlockSubmitDialog> createState() => _SponsorBlockSubmitDialogState();
}

class _SponsorBlockSubmitDialogState extends State<SponsorBlockSubmitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  SponsorSegmentCategory _selectedCategory = SponsorSegmentCategory.sponsor;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // 默认开始时间为当前播放时间前5秒，结束时间为当前时间
    final startTime = (widget.currentTime - 5).clamp(0.0, widget.currentTime);
    _startTimeController.text = startTime.toStringAsFixed(1);
    _endTimeController.text = widget.currentTime.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    _endTimeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // String _formatTime(double seconds) {
  //   final minutes = (seconds / 60).floor();
  //   final secs = (seconds % 60).floor();
  //   final millisecs = ((seconds % 1) * 10).floor();
  //   return '${minutes.toString().padLeft(2, '0')}:'
  //          '${secs.toString().padLeft(2, '0')}.'
  //          '${millisecs.toString()}';
  // }

  double? _parseTime(String timeStr) {
    try {
      // 支持多种时间格式：123.5, 2:03.5, 1:23:45.6
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        if (parts.length == 2) {
          // MM:SS.s 格式
          final minutes = int.parse(parts[0]);
          final seconds = double.parse(parts[1]);
          return minutes * 60 + seconds;
        } else if (parts.length == 3) {
          // HH:MM:SS.s 格式
          final hours = int.parse(parts[0]);
          final minutes = int.parse(parts[1]);
          final seconds = double.parse(parts[2]);
          return hours * 3600 + minutes * 60 + seconds;
        }
      } else {
        // 直接的秒数格式
        return double.parse(timeStr);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  void _onSubmit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final startTime = _parseTime(_startTimeController.text)!;
    final endTime = _parseTime(_endTimeController.text)!;
    final description = _descriptionController.text.trim();

    try {
      await widget.onSubmit(
        startTime,
        endTime,
        _selectedCategory,
        description.isEmpty ? null : description,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.content_cut, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Text('提交 SponsorBlock 片段'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视频ID显示
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.video_library, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    '视频: ${widget.videoId}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 片段类别选择
            const Text('片段类别', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<SponsorSegmentCategory>(
              value: _selectedCategory,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: Text(
                  _selectedCategory.icon,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
              ),
              items: SponsorSegmentCategory.values
                  .where((category) => category != SponsorSegmentCategory.poi_highlight)
                  .map((category) => DropdownMenuItem(
                        value: category,
                        child: Row(
                          children: [
                            Text(category.icon),
                            const SizedBox(width: 8),
                            Text(category.displayName),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                });
              },
            ),
            const SizedBox(height: 16),

            // 时间输入
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startTimeController,
                    decoration: const InputDecoration(
                      labelText: '开始时间',
                      hintText: '0:00.0',
                      border: OutlineInputBorder(),
                      suffixText: '秒',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入开始时间';
                      }
                      final time = _parseTime(value);
                      if (time == null) {
                        return '时间格式错误';
                      }
                      if (time < 0) {
                        return '时间不能为负数';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endTimeController,
                    decoration: const InputDecoration(
                      labelText: '结束时间',
                      hintText: '0:00.0',
                      border: OutlineInputBorder(),
                      suffixText: '秒',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入结束时间';
                      }
                      final endTime = _parseTime(value);
                      if (endTime == null) {
                        return '时间格式错误';
                      }
                      final startTime = _parseTime(_startTimeController.text);
                      if (startTime != null && endTime <= startTime) {
                        return '结束时间必须大于开始时间';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            
            // 快捷时间按钮
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.schedule, size: 16),
                  label: const Text('当前时间'),
                  onPressed: () {
                    _endTimeController.text = widget.currentTime.toStringAsFixed(1);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.remove, size: 16),
                  label: const Text('-5s'),
                  onPressed: () {
                    final current = _parseTime(_startTimeController.text) ?? 0;
                    _startTimeController.text = (current - 5).clamp(0, double.infinity).toStringAsFixed(1);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 描述（可选）
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '描述 (可选)',
                hintText: '为这个片段添加描述...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              maxLength: 100,
            ),
            const SizedBox(height: 8),

            // 提示信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, 
                       size: 16, 
                       color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '您的提交将帮助其他用户跳过${_selectedCategory.displayName}内容',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _onSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('提交'),
        ),
      ],
    );
  }
}

