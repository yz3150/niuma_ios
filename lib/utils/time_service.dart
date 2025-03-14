import 'package:flutter/material.dart';
import '../config/env_config.dart';

class TimeService {
  static final TimeService _instance = TimeService._internal();
  factory TimeService() => _instance;
  TimeService._internal();

  DateTime? _mockDateTime;

  DateTime now() {
    if (EnvConfig.isDev && _mockDateTime != null) {
      return _mockDateTime!;
    }
    return DateTime.now();
  }

  void setMockTime(DateTime dateTime) {
    if (EnvConfig.isDev) {
      _mockDateTime = dateTime;
    }
  }

  void resetToRealTime() {
    _mockDateTime = null;
  }
}

class TimeControlDialog extends StatefulWidget {
  final Function(DateTime) onTimeSelected;
  final DateTime? initialTime;

  const TimeControlDialog({
    super.key,
    required this.onTimeSelected,
    this.initialTime,
  });

  @override
  State<TimeControlDialog> createState() => _TimeControlDialogState();
}

class _TimeControlDialogState extends State<TimeControlDialog> {
  late DateTime _selectedTime;
  
  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('时间控制'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimeRow(),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () {
                  TimeService().resetToRealTime();
                  Navigator.pop(context);
                },
                child: const Text('使用真实时间'),
              ),
              ElevatedButton(
                onPressed: () {
                  widget.onTimeSelected(_selectedTime);
                  Navigator.pop(context);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTimeSpinner(
          value: _selectedTime.hour,
          maxValue: 23,
          label: '时',
          onChanged: (value) {
            setState(() {
              _selectedTime = DateTime(
                _selectedTime.year,
                _selectedTime.month,
                _selectedTime.day,
                value,
                _selectedTime.minute,
                _selectedTime.second,
              );
            });
          },
        ),
        const Text(':'),
        _buildTimeSpinner(
          value: _selectedTime.minute,
          maxValue: 59,
          label: '分',
          onChanged: (value) {
            setState(() {
              _selectedTime = DateTime(
                _selectedTime.year,
                _selectedTime.month,
                _selectedTime.day,
                _selectedTime.hour,
                value,
                _selectedTime.second,
              );
            });
          },
        ),
        const Text(':'),
        _buildTimeSpinner(
          value: _selectedTime.second,
          maxValue: 59,
          label: '秒',
          onChanged: (value) {
            setState(() {
              _selectedTime = DateTime(
                _selectedTime.year,
                _selectedTime.month,
                _selectedTime.day,
                _selectedTime.hour,
                _selectedTime.minute,
                value,
              );
            });
          },
        ),
      ],
    );
  }

  Widget _buildTimeSpinner({
    required int value,
    required int maxValue,
    required String label,
    required Function(int) onChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_drop_up),
          onPressed: () {
            final newValue = value < maxValue ? value + 1 : 0;
            onChanged(newValue);
          },
        ),
        Text(
          value.toString().padLeft(2, '0'),
          style: const TextStyle(fontSize: 20),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_drop_down),
          onPressed: () {
            final newValue = value > 0 ? value - 1 : maxValue;
            onChanged(newValue);
          },
        ),
        Text(label),
      ],
    );
  }
} 