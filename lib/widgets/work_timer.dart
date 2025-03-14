import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/time_service.dart';

class WorkTimer extends StatefulWidget {
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  const WorkTimer({
    super.key,
    required this.startTime,
    required this.endTime,
  });

  @override
  State<WorkTimer> createState() => _WorkTimerState();
}

class _WorkTimerState extends State<WorkTimer> {
  Timer? _timer;
  String _displayTime = "-:-:-";
  double _progress = 0.0;
  final TimeService _timeService = TimeService();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    // 立即更新一次
    _updateTime();
    
    // 每秒更新一次
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
    });
  }

  void _updateTime() {
    final now = _timeService.now();
    
    // 构建今天的日期时间
    final startDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      widget.startTime.hour,
      widget.startTime.minute,
    );
    
    final endDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      widget.endTime.hour,
      widget.endTime.minute,
    );

    setState(() {
      if (_isBeforeWorkTime(now)) {
        // 当前时间小于上班时间
        _displayTime = "-:-:-";
        _progress = 0.0;
      } else if (_isWithinWorkTime(now)) {
        // 在工作时间内
        final totalWorkDuration = endDateTime.difference(startDateTime).inSeconds;
        final elapsedDuration = now.difference(startDateTime).inSeconds;
        _progress = elapsedDuration / totalWorkDuration;
        final difference = now.difference(startDateTime);
        _displayTime = _formatDuration(difference);
      } else {
        // 超过下班时间
        _progress = 1.0;
        final difference = endDateTime.difference(startDateTime);
        _displayTime = _formatDuration(difference);
      }
    });
  }

  bool _isBeforeWorkTime(DateTime now) {
    final startDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      widget.startTime.hour,
      widget.startTime.minute,
    );
    return now.isBefore(startDateTime);
  }

  bool _isWithinWorkTime(DateTime now) {
    final startDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      widget.startTime.hour,
      widget.startTime.minute,
    );
    final endDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      widget.endTime.hour,
      widget.endTime.minute,
    );
    return now.isAfter(startDateTime) && now.isBefore(endDateTime) || now.isAtSameMomentAs(startDateTime);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: CircularProgressIndicator(
            value: _progress,
            strokeWidth: 8,
            backgroundColor: Colors.grey[200],
            color: Theme.of(context).primaryColor,
          ),
        ),
        Text(
          _displayTime,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
} 