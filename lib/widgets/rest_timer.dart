import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/time_service.dart';
import '../theme/app_theme.dart';
import '../utils/salary_calculator.dart';

class RestTimer extends StatefulWidget {
  final bool isResting;  // 是否正在摸鱼
  final Duration accumulatedTime;  // 已累积的摸鱼时长
  final Function(Duration) onTimeUpdate;  // 时间更新回调
  final String salaryType;  // 薪资类型
  final double salary;  // 薪资金额
  final bool isDataHidden;  // 是否隐藏数据
  final String? messageText;  // 基于摸鱼收入的随机文案

  const RestTimer({
    super.key,
    required this.isResting,
    required this.accumulatedTime,
    required this.onTimeUpdate,
    required this.salaryType,
    required this.salary,
    required this.isDataHidden,
    this.messageText,  // 添加可选的文案参数
  });

  @override
  State<RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends State<RestTimer> {
  Timer? _timer;
  late Duration _currentDuration;
  final TimeService _timeService = TimeService();
  DateTime? _lastUpdateTime;
  final ValueNotifier<double> _restEarningsNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _currentDuration = widget.accumulatedTime;
    _restEarningsNotifier.value = _calculateRestEarnings();
    
    if (widget.isResting) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(RestTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isResting != oldWidget.isResting) {
      if (widget.isResting) {
        _startTimer();
      } else {
        _stopTimer();
      }
    }
    
    // 如果薪资类型或金额变化，更新收入计算
    if (widget.salaryType != oldWidget.salaryType || 
        widget.salary != oldWidget.salary) {
      _restEarningsNotifier.value = _calculateRestEarnings();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _restEarningsNotifier.dispose();
    super.dispose();
  }

  void _startTimer() {
    _lastUpdateTime = _timeService.now();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final now = _timeService.now();
      if (_lastUpdateTime != null) {
        final increment = now.difference(_lastUpdateTime!);
        _currentDuration += increment;
        widget.onTimeUpdate(_currentDuration);
        
        // 更新摸鱼收入
        _restEarningsNotifier.value = _calculateRestEarnings();
        
        setState(() {});
      }
      _lastUpdateTime = now;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _lastUpdateTime = null;
  }

  double _calculateRestEarnings() {
    return SalaryCalculator.calculateRestEarnings(
      restDuration: _currentDuration,
      salaryType: widget.salaryType,
      salary: widget.salary,
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // 格式化金额的辅助方法
  String _formatAmount(double amount) {
    // 如果需要隐藏数据，返回星号
    if (widget.isDataHidden) {
      return '¥*****.**';
    }
    
    final formattedAmount = amount.toStringAsFixed(2);
    final parts = formattedAmount.split('.');
    final wholePart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    final decimalPart = parts[1];
    return '¥$wholePart.$decimalPart';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isResting) {
      // 摸鱼中状态 - 突出显示摸鱼收入
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 摸鱼时长 - 放在上方，样式不显眼
          Text(
            _formatDuration(_currentDuration),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              fontWeight: FontWeight.normal,
            ),
          ),
          const SizedBox(height: 8),
          // 摸鱼图标
          Icon(
            Icons.trending_up,
            size: 48,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(height: 24),
          // 摸鱼收入 - 中间最显眼位置
          ValueListenableBuilder<double>(
            valueListenable: _restEarningsNotifier,
            builder: (context, amount, child) {
              return Text(
                _formatAmount(amount),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              );
            },
          ),
          // 添加显示基于摸鱼收入的随机文案
          if (widget.messageText != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.messageText!,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ],
      );
    } else {
      // 非摸鱼状态 - 保持原有样式
      return Column(
        children: [
          Icon(
            Icons.trending_up,
            size: 48,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            _formatDuration(_currentDuration),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '今日已摸鱼时长',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ],
      );
    }
  }
} 