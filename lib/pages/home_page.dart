import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/work_timer.dart';
import '../widgets/rest_timer.dart';
import '../utils/time_service.dart';
import '../utils/salary_calculator.dart';
import '../utils/settings_service.dart';
import '../utils/holiday_service.dart';
import '../utils/notification_service.dart';
import '../config/env_config.dart';
import '../data/rest_earnings_messages.dart'; // 引入文案文件
import '../data/overtime_messages.dart'; // 引入加班文案文件
import 'dart:async';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart';
import 'dart:io';

enum WorkStatus {
  working,
  resting,
  offWork,
  overtime,
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  final TimeService _timeService = TimeService();
  final SettingsService _settingsService = SettingsService();
  final HolidayService _holidayService = HolidayService();
  final NotificationService _notificationService = NotificationService();
  WorkStatus _currentStatus = WorkStatus.working;
  Timer? _timer; // 主定时器
  Timer? _statusCheckTimer;
  Timer? _restStateSaveTimer;
  Timer? _hourlyRateUpdateTimer;
  final ValueNotifier<double> _currentRate = ValueNotifier(0);
  final ValueNotifier<double> _todayEarnings = ValueNotifier(0);
  final ValueNotifier<double> _restEarnings = ValueNotifier(0);
  final ValueNotifier<double> _yearToDateEarnings = ValueNotifier(0);
  final ValueNotifier<double> _weekRestEarnings = ValueNotifier(0);
  bool _isManualResting = false;
  bool _isManualOvertime = false;
  DateTime? _restStartTime;
  DateTime? _overtimeStartTime;
  Duration _restDuration = Duration.zero;
  Duration _overtimeDuration = Duration.zero;
  Duration _lastRestDuration = Duration.zero;
  Duration _lastOvertimeDuration = Duration.zero;
  final String _statusText = "一杯奶茶到手";
  
  // 添加数据隐藏状态变量
  bool _isDataHidden = false;
  
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late String _salaryType;
  late double _salary;

  // 添加保存应用状态的键
  static const String _isRestingKey = 'is_resting_state';
  static const String _restStartTimeKey = 'rest_start_time';
  static const String _lastRestDurationKey = 'last_rest_duration';
  // 加班状态键
  static const String _isOvertimeKey = 'is_overtime_state';
  static const String _overtimeStartTimeKey = 'overtime_start_time';
  static const String _lastOvertimeDurationKey = 'last_overtime_duration';
  // 添加记录上次加班日期的键
  static const String _lastOvertimeDateKey = 'last_overtime_date';
  // 添加记录上次重置计时器的日期键
  static const String _lastTimerResetDateKey = 'last_timer_reset_date';

  String? _lastSavedDailyDataDate; // 记录最后一次保存每日数据的日期

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _settingsService.settingsChangedNotifier.addListener(_handleSettingsChanged);
    
    // 初始化当前时薪通知器的值为标准时薪
    _currentRate.value = _settingsService.getHourlySalary();
    
    // 恢复上次的摸鱼状态
    _restoreRestState();
    
    // 清理可能存在的旧定时器
    _timer?.cancel();
    
    // 每秒更新状态和加班时长
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateStatus();
        _updateTodayEarnings();
        _updateOvertimeDuration();
        _updateRestDuration(); // 添加摸鱼时长更新
        _updateCurrentHourlyRate(); // 添加当前时薪更新
        _saveRestStateIfNeeded(); // 定期保存摸鱼时长
      }
    });
    
    print('初始化完成，定时器已启动');
  }

  @override
  void dispose() {
    print('正在清理资源...');
    _timer?.cancel();
    _timer = null;
    _hourlyRateUpdateTimer?.cancel(); // 确保释放高频率定时器
    _hourlyRateUpdateTimer = null;
    // 移除不必要的收入卡片定时器清理
    _settingsService.settingsChangedNotifier.removeListener(_handleSettingsChanged);
    _currentRate.dispose(); // 释放通知器资源
    super.dispose();
  }

  void _handleSettingsChanged() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _startTime = _settingsService.getStartTime();
      _endTime = _settingsService.getEndTime();
      _salaryType = _settingsService.getSalaryType();
      _salary = _settingsService.getSalary();
      
      // 更新当前时薪通知器的值为最新的标准时薪
      _currentRate.value = _settingsService.getHourlySalary();
    });
    
    if (_timer == null) {
      _startTimer();
    } else {
      _updateStatus();
      _updateTodayEarnings();
    }
    
    // 如果当前是加班状态，确保高频率定时器运行
    if (_currentStatus == WorkStatus.overtime && _hourlyRateUpdateTimer == null) {
      _startHighFrequencyHourlyRateUpdate();
    }
  }

  void _startTimer() {
    // 立即更新一次状态和收入
    _updateStatus();
    _updateTodayEarnings();
    
    // 每秒更新一次状态和收入
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateStatus();
      _updateTodayEarnings();
    });
  }

  void _updateStatus() {
    // 获取当前日期时间
    final now = _timeService.now();
    final todayDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    
    // 检查是否为周末或节假日
    final isHoliday = _holidayService.isHoliday(now);
    final isSpecialWorkDay = _holidayService.isWorkday(now); // 调休上班日
    
    // 检查当前是否在工作时间内，使用精确的方法
    final bool isWorkTime = _isExactlyWithinWorkTime(now);
    
    // 检查是否到达下班时间，使用精确的方法
    final bool isEndOfWorkday = _isExactlyAtOrPastEndTime(now);
    
    // 否则，周一至周五是工作日，周六日不是工作日
    final bool isWeekday = now.weekday <= 5; // 1-5 对应周一至周五
    final bool isWorkDay = isSpecialWorkDay || (!isHoliday && isWeekday);
    
    // 检查是否需要重置所有计时器（上班时间到达时），使用精确到秒的判断
    if (isWorkDay && _isAtStartTime(now)) {
      print('检测到上班时间到达：${now.hour}:${now.minute}:${now.second}，准备重置计时器');
      // 这是一个异步调用，但我们不需要等待它完成
      _checkAndResetAllTimers(todayDateStr);
    }
    
    // 检查今天是否是新的工作日，需要重置加班时长
    _checkAndResetOvertimeDuration(isWorkDay, isWorkTime, todayDateStr);
    
    // 记录当前状态用于后续判断是否发生了状态变化
    final previousStatus = _currentStatus;
    WorkStatus newStatus = _currentStatus; // 先假设状态不变
    
    // 根据当前情况计算新状态
    if (isWorkDay && isWorkTime) {
      // 在工作日的工作时间内
      if (_isManualResting) {
        newStatus = WorkStatus.resting;
      } else {
        newStatus = WorkStatus.working;
      }
    } else {
      // 非工作时间或非工作日
      if (_isManualOvertime) {
        newStatus = WorkStatus.overtime;
      } else {
        // 如果是下班时间且用户处于摸鱼状态，强制切换为下班状态
        if (_currentStatus == WorkStatus.resting && isEndOfWorkday) {
          _isManualResting = false; // 重置手动摸鱼状态
        }
        newStatus = WorkStatus.offWork;
      }
    }
    
    // 只有当状态发生变化时才调用setState
    if (newStatus != _currentStatus) {
      print('自动状态切换: ${_currentStatus.toString()} -> ${newStatus.toString()}');
      setState(() {
        _currentStatus = newStatus;
      });
    }
    
    // 如果状态从摸鱼中变为下班中，则保存摸鱼数据并清理状态
    if (previousStatus == WorkStatus.resting && _currentStatus == WorkStatus.offWork) {
      // 保存当前摸鱼时长
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (_restStartTime != null) {
        // 计算最终摸鱼时长
        final currentSessionDuration = now.difference(_restStartTime!);
        _lastRestDuration = _lastRestDuration + currentSessionDuration;
        _restDuration = _lastRestDuration;
        
        // 保存摸鱼时长到每日统计
        _settingsService.setDailyRestMinutes(dateStr, _restDuration.inMinutes);
        
        // 清除摸鱼状态
        _restStartTime = null;
        _isManualResting = false;
        _saveRestDuration();
        print('摸鱼状态自动结束，已保存摸鱼时长');
      }
    }
    
    // 如果状态从加班中变为下班中，则保存加班数据并清理状态
    if (previousStatus == WorkStatus.overtime && _currentStatus == WorkStatus.offWork) {
      if (_overtimeStartTime != null) {
        // 计算最终加班时长（包含当前会话）
        final currentSessionDuration = now.difference(_overtimeStartTime!);
        _lastOvertimeDuration = _lastOvertimeDuration + currentSessionDuration;
        _overtimeDuration = _lastOvertimeDuration;
        _overtimeStartTime = null;
        
        // 停止高频率更新当前时薪
        _stopHighFrequencyHourlyRateUpdate();
        
        // 保存当前加班时长
        _saveOvertimeDuration();
      }
      print('状态切换: 加班中 -> 下班中');
    }
    
    // 获取当前日期字符串
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    // 新的保存数据触发条件：
    // 1. 上班时间刚到（早上），用于保存前一天的数据
    // 2. 当前是工作日
    // 3. 前一天的数据尚未保存
    if (isWorkDay && _isAtStartTime(now) && yesterdayStr != _lastSavedDailyDataDate) {
      // 保存昨天的数据
      _saveDailyData(yesterdayStr);
    }
  }

  void _updateTodayEarnings() {
    // 只更新_todayEarnings变量，不触发UI重建
    _todayEarnings.value = SalaryCalculator.calculateTodayEarnings(
      currentTime: _timeService.now(),
      startTime: _startTime,
      endTime: _endTime,
      salaryType: _salaryType,
      salary: _salary,
    );
  }

  bool _isWithinWorkTime(DateTime now) {
    // 创建表示今天上班和下班时间的完整DateTime对象
    final workStartDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _startTime.hour,
      _startTime.minute,
    );
    
    final workEndDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _endTime.hour,
      _endTime.minute,
    );
    
    // 检查当前时间是否在工作时间内
    return (now.isAfter(workStartDateTime) || now.isAtSameMomentAs(workStartDateTime)) && 
           now.isBefore(workEndDateTime);
  }

  bool _isAtOrPastEndTime(DateTime now) {
    // 创建表示今天下班时间的完整DateTime对象
    final workEndDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _endTime.hour,
      _endTime.minute,
    );
    
    // 检查当前时间是否等于或超过下班时间
    return now.isAtSameMomentAs(workEndDateTime) || now.isAfter(workEndDateTime);
  }

  // 检查是否刚好到达上班时间，精确到秒级
  bool _isAtStartTime(DateTime now) {
    // 创建表示今天上班时间的完整DateTime对象，精确到秒
    final workStartDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _startTime.hour,
      _startTime.minute,
      0, // 秒设为0
    );
    
    // 计算当前时间与上班时间的差异（秒）
    final differenceInSeconds = now.difference(workStartDateTime).inSeconds;
    
    // 为了确保不会错过上班时间点，我们扩大检测窗口
    // 只要当前时间在上班时间的前10秒到后5秒范围内，就认为是上班时间
    return differenceInSeconds >= -10 && differenceInSeconds <= 5;
  }
  
  // 获取实际下班时间，考虑加班情况
  DateTime _getActualEndTime(String dateStr) {
    final now = _timeService.now();
    final date = DateTime(now.year, now.month, now.day);
    
    // 解析日期字符串
    final parts = dateStr.split('-');
    final targetDate = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    
    // 标准下班时间
    final standardEndTime = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      _endTime.hour,
      _endTime.minute,
    );
    
    // 获取该日期的加班时长（分钟）
    final overtimeMinutes = _settingsService.getOvertimeMinutes(dateStr);
    
    // 如果有加班，则将加班时长添加到标准下班时间
    if (overtimeMinutes > 0) {
      return standardEndTime.add(Duration(minutes: overtimeMinutes));
    } else {
      return standardEndTime;
    }
  }

  void _handleStatusButtonPressed() {
    final now = _timeService.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    // 记录切换前的状态，用于调试
    final prevStatus = _currentStatus;
    
    setState(() {
      switch (_currentStatus) {
        case WorkStatus.working:
          // 搬砖中 -> 摸鱼中
          _isManualResting = true;
          _currentStatus = WorkStatus.resting;
          // 使用上次保存的完整摸鱼时长（包含秒）
          _restDuration = _lastRestDuration;
          // 记录摸鱼开始时间为当前时间
          _restStartTime = now;
          // 立即保存状态，避免意外退出导致状态丢失
          print('状态切换: 搬砖中 -> 摸鱼中');
          break;
        case WorkStatus.resting:
          // 摸鱼中 -> 搬砖中
          _isManualResting = false;
          _currentStatus = WorkStatus.working;
          // 保存当前完整的摸鱼时长（包含秒）用于下次恢复
          if (_restStartTime != null) {
            // 保存当前完整的摸鱼时长（包含秒）用于下次恢复
            _lastRestDuration = _restDuration;
            
            // 仍然以分钟精度保存到SharedPreferences
            final restMinutes = _restDuration.inMinutes;
            _settingsService.setDailyRestMinutes(dateStr, restMinutes);
            
            _restStartTime = null;
          }
          print('状态切换: 摸鱼中 -> 搬砖中');
          break;
        case WorkStatus.offWork:
          // 下班中 -> 加班中
          _isManualOvertime = true;
          _currentStatus = WorkStatus.overtime;
          // 使用上次保存的完整时长（包含秒）
          _overtimeDuration = _lastOvertimeDuration;
          // 记录加班开始时间为当前时间
          _overtimeStartTime = now;
          // 启动高频率更新当前时薪
          print('状态切换: 下班中 -> 加班中');
          break;
        case WorkStatus.overtime:
          // 加班中 -> 下班中
          _isManualOvertime = false;
          _currentStatus = WorkStatus.offWork;
          // 保存加班时长但不重置，以便下次继续累计
          if (_overtimeStartTime != null) {
            // 计算最终加班时长（包含当前会话）
            final currentSessionDuration = now.difference(_overtimeStartTime!);
            _lastOvertimeDuration = _lastOvertimeDuration + currentSessionDuration;
            _overtimeDuration = _lastOvertimeDuration;
            
            // 停止加班计时
            _overtimeStartTime = null;
            
            // 停止高频率更新当前时薪
            _stopHighFrequencyHourlyRateUpdate();
          }
          print('状态切换: 加班中 -> 下班中');
          break;
      }
    });

    // 状态切换后立即执行一次状态相关的保存操作
    if (prevStatus == WorkStatus.working && _currentStatus == WorkStatus.resting) {
      _saveRestDuration();
    } else if (prevStatus == WorkStatus.resting && _currentStatus == WorkStatus.working) {
      _saveRestDuration();
    } else if (prevStatus == WorkStatus.offWork && _currentStatus == WorkStatus.overtime) {
      _saveOvertimeDuration();
      _startHighFrequencyHourlyRateUpdate();
    } else if (prevStatus == WorkStatus.overtime && _currentStatus == WorkStatus.offWork) {
      _saveOvertimeDuration();
    }

    // 强制更新UI状态
    print('状态切换完成，当前状态: ${_currentStatus.toString()}');
    // 主动调用一次状态更新
    _updateStatus();
  }

  void _handleRestDurationUpdate(Duration duration) {
    // 更新_restDuration变量，专用于外部传入的累计时长
    _restDuration = duration;
    
    // 仅在分钟数变化时更新存储（仍然只存储分钟精度到SharedPreferences）
    final now = _timeService.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final storedMinutes = _settingsService.getDailyRestMinutes(dateStr);
    
    if (duration.inMinutes != storedMinutes) {
      _settingsService.setDailyRestMinutes(dateStr, duration.inMinutes);
    }
  }

  void _updateOvertimeDuration() {
    if (_currentStatus == WorkStatus.overtime && _overtimeStartTime != null) {
      final now = _timeService.now();
      
      // 计算当前加班会话的时长
      final currentSessionDuration = now.difference(_overtimeStartTime!);
      
      // 总加班时长 = 上次保存的时长 + 当前会话时长
      final newOvertimeDuration = _lastOvertimeDuration + currentSessionDuration;
      
      // 只有当加班时长有变化时才更新UI
      if (newOvertimeDuration.inSeconds != _overtimeDuration.inSeconds) {
        // 移除setState调用，直接更新时长并调用handler
        _overtimeDuration = newOvertimeDuration;
        
        // 通知更新，类似_handleRestDurationUpdate
        _handleOvertimeDurationUpdate(_overtimeDuration);
      }
    }
  }

  // 添加新方法：处理加班时长更新，类似于摸鱼时长更新处理
  void _handleOvertimeDurationUpdate(Duration duration) {
    // 更新_overtimeDuration变量
    _overtimeDuration = duration;
    
    // 仅在分钟数变化时更新存储
    final now = _timeService.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final storedMinutes = _settingsService.getOvertimeMinutes(dateStr);
    
    if (duration.inMinutes != storedMinutes) {
      _settingsService.setOvertimeMinutes(dateStr, duration.inMinutes);
    }
    
    // 如果在加班状态下，更新状态卡片中的计时器显示
    if (_currentStatus == WorkStatus.overtime) {
      setState(() {
        // 这里不需要更新_overtimeDuration，因为上面已经更新了
        // 这个setState只是为了触发UI刷新计时器显示
      });
    }
  }

  // 添加方法来更新摸鱼时长，与加班时长更新类似
  void _updateRestDuration() {
    if (_currentStatus == WorkStatus.resting && _restStartTime != null) {
      final now = _timeService.now();
      
      // 计算当前摸鱼会话的时长
      final currentSessionDuration = now.difference(_restStartTime!);
      
      // 总摸鱼时长 = 上次保存的时长 + 当前会话时长
      final newRestDuration = _lastRestDuration + currentSessionDuration;
      
      // 只有当摸鱼时长有变化时才传递更新
      if (newRestDuration.inSeconds != _restDuration.inSeconds) {
        _restDuration = newRestDuration;
        
        // 通知RestTimer组件更新显示
        if (_currentStatus == WorkStatus.resting) {
          // 不直接在这里调用setState，让RestTimer组件自己处理UI更新
          _handleRestDurationUpdate(_restDuration);
        }
      }
    }
  }

  // 添加方法来更新当前时薪
  void _updateCurrentHourlyRate() {
    final now = _timeService.now();
    
    if (_currentStatus == WorkStatus.overtime) {
      // 加班状态下，实时计算实际时薪
      
      // 计算实际工作开始时间
      final startDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        _startTime.hour,
        _startTime.minute,
      );
      
      // 计算总工作时长（分钟）
      final totalWorkMinutes = now.difference(startDateTime).inMinutes;
      
      // 计算今日总收入
      final todayEarnings = SalaryCalculator.calculateTodayEarnings(
        currentTime: now,
        startTime: _startTime,
        endTime: _endTime,
        salaryType: _salaryType,
        salary: _salary,
      );
      
      // 计算实际时薪（包含加班的实际表现）
      final hourlyRate = totalWorkMinutes > 0
        ? (todayEarnings / totalWorkMinutes * 60)
        : _settingsService.getHourlySalary();
        
      // 更新通知器，触发UI更新
      if (hourlyRate != _currentRate.value) {
        _currentRate.value = hourlyRate;
      }
    } else if (_currentStatus == WorkStatus.working || _currentStatus == WorkStatus.resting) {
      // 搬砖中或摸鱼中状态下，始终使用标准时薪
      final standardHourlyRate = _salaryType == '时薪'
        ? _salary
        : _settingsService.getHourlySalary();
        
      // 更新通知器，触发UI更新
      if (standardHourlyRate != _currentRate.value) {
        _currentRate.value = standardHourlyRate;
      }
    }
    // 在下班状态下不更新时薪，保持当前值
  }

  // 在状态变为加班时启动高频率更新
  void _startHighFrequencyHourlyRateUpdate() {
    // 取消之前的定时器（如果存在）
    _hourlyRateUpdateTimer?.cancel();
    
    // 创建新的高频率定时器 - 每16毫秒更新一次（约60FPS）
    _hourlyRateUpdateTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _updateCurrentHourlyRate();
    });
  }
  
  // 在状态不是加班时停止高频率更新
  void _stopHighFrequencyHourlyRateUpdate() {
    _hourlyRateUpdateTimer?.cancel();
    _hourlyRateUpdateTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    // 在build方法中直接计算最新的收入数据
    final todayEarnings = SalaryCalculator.calculateTodayEarnings(
      currentTime: _timeService.now(),
      startTime: _startTime,
      endTime: _endTime,
      salaryType: _salaryType,
      salary: _salary,
    );
    
    final restEarnings = SalaryCalculator.calculateRestEarnings(
      restDuration: _restDuration,
      salaryType: _salaryType,
      salary: _salary,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('牛马'),
        actions: [
          // 添加数据隐藏/显示切换按钮
          IconButton(
            icon: Icon(_isDataHidden ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                _isDataHidden = !_isDataHidden;
              });
            },
            tooltip: _isDataHidden ? '显示数据' : '隐藏数据',
          ),
          if (EnvConfig.isDev)
            IconButton(
              icon: const Icon(Icons.access_time),
              onPressed: _showTimeControlDialog,
            ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showExportConfirmDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (EnvConfig.isDev) _buildMockTimeDisplay(),
            _buildStatusCard(),
            const SizedBox(height: 16),
            // 使用最新计算的数据构建收入部分
            _buildEarningsSection(todayEarnings: todayEarnings, restEarnings: restEarnings),
          ],
        ),
      ),
    );
  }

  // 下拉刷新处理函数
  Future<void> _handleRefresh() async {
    // 显示刷新消息
    _showMessage('正在刷新数据...');
    
    // 加载最新设置
    await _loadSettings();
    
    // 更新工作状态和统计数据
    _updateStatus();
    _updateTodayEarnings();
    _updateOvertimeDuration();
    _updateRestDuration();
    _updateCurrentHourlyRate();
    
    // 如果是开发环境，重置模拟时间为实际时间
    if (EnvConfig.isDev) {
      _timeService.resetToRealTime();
    }
    
    // 显示刷新完成消息
    _showMessage('数据已刷新');
    
    // 等待一小段时间以确保UI更新
    return Future.delayed(const Duration(milliseconds: 500));
  }

  Widget _buildMockTimeDisplay() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.amber[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (context, snapshot) {
              final now = _timeService.now();
              return Text(
                '模拟时间：${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(
        minHeight: 400,  // 设置固定最小高度
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,  // 在顶部和底部之间均匀分布
        children: [
          Text(
            _getStatusTitle(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          _buildStatusContent(),  // 中间内容
          SizedBox(  // 固定按钮容器大小
            width: 200,
            height: 45,
            child: ElevatedButton(
              onPressed: _handleStatusButtonPressed,
              child: Text(_getButtonText()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusContent() {
    print('构建状态内容，当前状态: ${_currentStatus.toString()}');
    switch (_currentStatus) {
      case WorkStatus.working:
        return SizedBox(
          height: 245,  // 增加高度，解决3像素溢出问题
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,  // 使列尽可能小
              children: [
                Flexible(  // 使WorkTimer可伸缩
                  child: WorkTimer(
                    startTime: _startTime,
                    endTime: _endTime,
                  ),
                ),
                const SizedBox(height: 8),  // 再减小间距
                StreamBuilder(
                  stream: Stream.periodic(const Duration(seconds: 1)),
                  builder: (context, snapshot) {
                    final now = _timeService.now();
                    final endDateTime = DateTime(
                      now.year, 
                      now.month, 
                      now.day, 
                      _endTime.hour, 
                      _endTime.minute
                    );
                    
                    // 如果已经过了下班时间，显示0
                    var remainingDuration = now.isAfter(endDateTime) 
                        ? Duration.zero 
                        : endDateTime.difference(now);
                    
                    final hours = remainingDuration.inHours;
                    final minutes = remainingDuration.inMinutes % 60;
                    final seconds = remainingDuration.inSeconds % 60;
                    
                    return Text(
                      '距离下班还有 $hours小时$minutes分',
                      style: TextStyle(
                        fontSize: 13,  // 进一步减小字体大小
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      case WorkStatus.resting:
        // 计算当前摸鱼收入
        final restEarnings = SalaryCalculator.calculateRestEarnings(
          restDuration: _restDuration,
          salaryType: _salaryType,
          salary: _salary,
        );
        
        // 使用导入的getRandomRestEarningMessage方法获取文案
        final messageText = getRandomRestEarningMessage(restEarnings);
        
        return SizedBox(
          height: 290, // 增加高度以确保容纳所有内容，原来是280，再增加10像素
          child: Center(
            child: RestTimer(
              isResting: true,
              accumulatedTime: _restDuration,
              onTimeUpdate: _handleRestDurationUpdate,
              salaryType: _salaryType,
              salary: _salary,
              isDataHidden: _isDataHidden,
              messageText: messageText, // 传递随机文案
            ),
          ),
        );
      case WorkStatus.overtime:
        // 获取加班文案
        final messageText = getRandomOvertimeMessage(_overtimeDuration);
        
        // 计算加班收入 - 使用时薪和当前加班时长
        final overtimeHours = _overtimeDuration.inMilliseconds / (1000 * 60 * 60);
        final hourlyRate = _salaryType == '时薪'
          ? _salary
          : _settingsService.getHourlySalary();
        final overtimeEarnings = overtimeHours * hourlyRate;
        
        // 格式化加班收入
        final formattedEarnings = _isDataHidden 
          ? '¥*****.**' 
          : _formatAmount(overtimeEarnings);
        
        return SizedBox(
          height: 240,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 加班时长 - 放在上方，样式不显眼
                Text(
                  '${_overtimeDuration.inHours.toString().padLeft(2, '0')}:${(_overtimeDuration.inMinutes % 60).toString().padLeft(2, '0')}:${(_overtimeDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 8),
                // 加班图标
                const Icon(
                  Icons.psychology_alt, 
                  size: 48, 
                  color: AppTheme.primaryColor
                ),
                const SizedBox(height: 24),
                // 加班收入 - 中间最显眼位置
                Text(
                  formattedEarnings,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                // 添加显示加班文案的容器
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    messageText,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        );
      case WorkStatus.offWork:
        // 计算今日摸鱼收入
        final restEarnings = SalaryCalculator.calculateRestEarnings(
          restDuration: _restDuration,
          salaryType: _salaryType,
          salary: _salary,
        );
        
        // 计算摸鱼收入占比
        final percentage = _todayEarnings.value > 0 
          ? (restEarnings / _todayEarnings.value * 100).toStringAsFixed(1)
          : '0.0';
        
        return SizedBox(
          height: 240,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 减小顶部间距，让图标更靠近标题
                const SizedBox(height: 8),
                // sprint图标放在进度条上方
                Icon(
                  Icons.directions_run,
                  size: 48,
                  color: AppTheme.primaryColor,
                ),
                // 增加图标到进度条的间距
                const SizedBox(height: 32),
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    value: _todayEarnings.value > 0 ? restEarnings / _todayEarnings.value : 0,
                    backgroundColor: Colors.grey[200],
                    color: AppTheme.primaryColor,
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  // 不再使用数据隐藏功能，始终显示真实百分比
                '今日收入$percentage%为摸鱼所得哦~',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildEarningsSection({required double todayEarnings, required double restEarnings}) {
    // 计算正常工作时长（分钟）
    final now = _timeService.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    // 获取今日加班时长(用于其他计算，不再用于时薪计算)
    final overtimeMinutes = _currentStatus == WorkStatus.overtime
        ? _overtimeDuration.inMinutes
        : _settingsService.getOvertimeMinutes(dateStr);

    // 计算标准工作时长（分钟）
    final workStartDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _startTime.hour,
      _startTime.minute,
    );
    
    final workEndDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _endTime.hour,
      _endTime.minute,
    );
    
    final standardWorkMinutes = workEndDateTime.difference(workStartDateTime).inMinutes;
    
    // 计算总工作时长（标准工作时长+加班时长）(分钟)
    final totalWorkMinutes = standardWorkMinutes + overtimeMinutes;
    
    // 计算实际时薪 - 根据不同状态使用不同的计算方式
    double hourlyRate;
    
    // 对于搬砖中和摸鱼中状态，使用标准时薪
    if (_currentStatus == WorkStatus.working || _currentStatus == WorkStatus.resting) {
      // 直接使用额定时薪
      hourlyRate = _salaryType == '时薪'
        ? _salary
        : _settingsService.getHourlySalary();
    } 
    // 对于加班中和下班中状态，计算实际时薪（如果有工作时间）
    else {
      if (totalWorkMinutes > 0) {
        // 将分钟转换为小时，计算实际时薪
        hourlyRate = todayEarnings / (totalWorkMinutes / 60);
      } else {
        // 如果没有工作时长，使用标准时薪
        hourlyRate = _salaryType == '时薪'
          ? _salary
          : _settingsService.getHourlySalary();
      }
    }

    // 计算今年搬砖收入（历史数据）
    final yearToDateEarnings = SalaryCalculator.calculateYearToDateEarnings(
      currentTime: _timeService.now(),
      salaryType: _salaryType,
      salary: _salary,
    );

    // 计算本周摸鱼收入
    final weekRestEarnings = SalaryCalculator.calculateWeekRestEarnings(
      currentTime: _timeService.now(),
      todayRestDuration: _restDuration,
      salaryType: _salaryType,
      salary: _salary,
    );

    // 判断是否应该置灰
    bool shouldGrayOutTodayEarnings = _currentStatus == WorkStatus.offWork || 
        (_currentStatus == WorkStatus.overtime);
    
    // 修改：使今日摸鱼卡片在下班中和加班中状态下置灰
    bool shouldGrayOutRestEarnings = _currentStatus == WorkStatus.offWork || 
        (_currentStatus == WorkStatus.overtime);
        
    // 修改：时薪卡片在加班中状态下不置灰
    bool shouldGrayOutHourlyRate = _currentStatus == WorkStatus.offWork;
    
    // 新增：今日加班卡片在下班状态下置灰，加班状态下不置灰
    bool shouldGrayOutOvertimeEarnings = _currentStatus == WorkStatus.offWork;
    
    // 新增：所有卡片在摸鱼状态和工作状态下都不置灰
    bool shouldGrayOutAllCards = _currentStatus == WorkStatus.offWork || 
        (_currentStatus == WorkStatus.overtime);

    return Column(
      children: [
        // 第一行：今日搬砖 今日摸鱼
        Row(
          children: [
            Expanded(
              child: RealtimeEarningsCard(
                title: '今日搬砖',
                amountCalculator: () => SalaryCalculator.calculateTodayEarnings(
                  currentTime: _timeService.now(),
                  startTime: _startTime,
                  endTime: _endTime,
                  salaryType: _salaryType,
                  salary: _salary,
                ),
                shouldGrayOut: shouldGrayOutTodayEarnings,
                timeService: _timeService,
                isDataHidden: _isDataHidden,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: RealtimeEarningsCard(
                title: '今日摸鱼',
                amountCalculator: () => SalaryCalculator.calculateRestEarnings(
                  restDuration: _restDuration,
                  salaryType: _salaryType,
                  salary: _salary,
                ),
                shouldGrayOut: shouldGrayOutRestEarnings,
                timeService: _timeService,
                isDataHidden: _isDataHidden,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // 第二行：今日时薪 今日加班
        Row(
          children: [
            Expanded(
              child: _currentStatus == WorkStatus.overtime 
                // 加班状态下，使用实时计算的时薪
                ? RealtimeEarningsCard(
                    title: '今日时薪',
                    amountCalculator: () {
                      // 重新计算实时时薪
                      final now = _timeService.now();
                      final currentOvertimeMinutes = _currentStatus == WorkStatus.overtime
                          ? _overtimeDuration.inMinutes
                          : _settingsService.getOvertimeMinutes(dateStr);
                      
                      final totalWorkMinutes = standardWorkMinutes + currentOvertimeMinutes;
                      
                      // 加班状态下，继续使用实时计算的时薪
                      if (totalWorkMinutes > 0) {
                        final currentTodayEarnings = SalaryCalculator.calculateTodayEarnings(
                          currentTime: now,
                          startTime: _startTime,
                          endTime: _endTime,
                          salaryType: _salaryType,
                          salary: _salary,
                        );
                        return currentTodayEarnings / (totalWorkMinutes / 60);
                      } else {
                        return _salaryType == '时薪'
                          ? _salary
                          : _settingsService.getHourlySalary();
                      }
                    },
                    shouldGrayOut: false,
                    timeService: _timeService,
                    isDataHidden: _isDataHidden,
                  )
                // 非加班状态，使用普通卡片
                : _buildEarningsCard('今日时薪', hourlyRate, shouldGrayOut: shouldGrayOutHourlyRate),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _currentStatus == WorkStatus.overtime
                ? RealtimeEarningsCard(
                    title: '今日加班',
                    amountCalculator: () {
                      // 使用时薪和当前加班时长计算加班收入
                      final overtimeHours = _overtimeDuration.inMilliseconds / (1000 * 60 * 60);
                      final hourlyRate = _salaryType == '时薪'
                        ? _salary
                        : _settingsService.getHourlySalary();
                      return overtimeHours * hourlyRate;
                    },
                    shouldGrayOut: false, // 加班状态下不置灰加班卡片
                    timeService: _timeService,
                    isDataHidden: _isDataHidden,
                  )
                : RealtimeEarningsCard(
                    title: '今日加班',
                    amountCalculator: () {
                      // 统一使用_overtimeDuration，不再使用_lastOvertimeDuration
                      // 这与摸鱼卡片的实现保持一致
                      final overtimeHours = _overtimeDuration.inMilliseconds / (1000 * 60 * 60);
                      final hourlyRate = _salaryType == '时薪'
                        ? _salary
                        : _settingsService.getHourlySalary();
                      return overtimeHours * hourlyRate;
                    },
                    shouldGrayOut: shouldGrayOutOvertimeEarnings, // 使用变量控制置灰
                    timeService: _timeService,
                    isDataHidden: _isDataHidden,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // 第三行：今年搬砖 本周摸鱼 放假倒计时
        Row(
          children: [
            Expanded(
              child: _buildEarningsCard('今年搬砖(不含今日)', yearToDateEarnings),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildEarningsCard('本周摸鱼(不含今日)', weekRestEarnings),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: HolidayCountdownCard(
                timeService: _timeService,
                holidayService: _holidayService,
                shouldGrayOut: shouldGrayOutAllCards, // 在加班和下班状态下置灰
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEarningsCard(String title, double amount, {bool? shouldGrayOut}) {
    // 下班状态和加班状态时的置灰效果，现在包括今日时薪在内的所有非摸鱼卡片都会置灰
    final bool shouldGrayOutCard = shouldGrayOut ?? (_currentStatus == WorkStatus.offWork || 
        (_currentStatus == WorkStatus.overtime)); // 在下班和加班状态下置灰所有卡片
    
    final Color backgroundColor = shouldGrayOutCard ? Colors.grey[100]! : Colors.white;
    final Color textColor = shouldGrayOutCard ? Colors.grey[500]! : Colors.grey;
    final Color amountColor = shouldGrayOutCard ? Colors.grey[600]! : Colors.black87;
    
    // 获取金额文本，根据隐藏状态决定是否显示星号
    final String amountText = _isDataHidden ? '¥*****.**' : _formatAmount(amount);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            amountText,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusTitle() {
    switch (_currentStatus) {
      case WorkStatus.working:
        return '搬砖中';
      case WorkStatus.resting:
        return '摸鱼中';
      case WorkStatus.offWork:
        return '下班中';
      case WorkStatus.overtime:
        return '加班中';
    }
  }

  String _getButtonText() {
    print('获取按钮文本，当前状态: ${_currentStatus.toString()}');
    switch (_currentStatus) {
      case WorkStatus.working:
        return '开始摸鱼';
      case WorkStatus.resting:
        return '结束摸鱼';
      case WorkStatus.offWork:
        return '开始加班';
      case WorkStatus.overtime:
        return '结束加班';
    }
  }

  String _getTimeDisplay() {
    return '10:00:00';
  }

  void _showTimeControlDialog() {
    showDialog(
      context: context,
      builder: (context) => TimeControlDialog(
        initialTime: _timeService.now(),
        onTimeSelected: (dateTime) {
          _timeService.setMockTime(dateTime);
          _updateStatus();
        },
      ),
    );
  }

  // 保存每日数据
  Future<void> _saveDailyData(String dateStr) async {
    // 计算并保存今日搬砖收入
    final todayEarnings = SalaryCalculator.calculateTodayEarnings(
      currentTime: _timeService.now(),
      startTime: _startTime,
      endTime: _endTime,
      salaryType: _salaryType,
      salary: _salary,
    );
    await _settingsService.setDailyEarnings(dateStr, todayEarnings);
    
    // 计算并保存今日摸鱼收入
    final restEarnings = SalaryCalculator.calculateRestEarnings(
      restDuration: _restDuration,
      salaryType: _salaryType,
      salary: _salary,
    );
    await _settingsService.setDailyRestEarnings(dateStr, restEarnings);
    
    // 保存今日摸鱼时长和加班时长
    await _settingsService.setDailyRestMinutes(dateStr, _restDuration.inMinutes);
    await _settingsService.setOvertimeMinutes(dateStr, _overtimeDuration.inMinutes);
    
    // 保存当天的上班时间
    await _settingsService.setDailyStartTime(dateStr, _startTime);
    
    // 获取并保存实际下班时间（考虑加班情况）
    final actualEndTime = _getActualEndTime(dateStr);
    final actualEndTimeOfDay = TimeOfDay(hour: actualEndTime.hour, minute: actualEndTime.minute);
    await _settingsService.setDailyEndTime(dateStr, actualEndTimeOfDay);
    
    // 计算实际工作时长（包含加班）
    final workStartDateTime = DateTime(
      actualEndTime.year,
      actualEndTime.month,
      actualEndTime.day,
      _startTime.hour,
      _startTime.minute,
    );
    
    // 计算实际工作分钟数（包含加班时间）
    final workDurationMinutes = actualEndTime.difference(workStartDateTime).inMinutes;
    await _settingsService.setDailyWorkMinutes(dateStr, workDurationMinutes);
    
    // 计算并保存时薪（今日搬砖/(下班时间-上班时间)）
    double hourlyRate;
    if (workDurationMinutes > 0) {
      // 将工作分钟转换为小时，计算实际时薪
      hourlyRate = todayEarnings / (workDurationMinutes / 60);
    } else {
      // 如果工作时长为0，使用标准时薪
      hourlyRate = _salaryType == '时薪'
        ? _salary
        : _settingsService.getHourlySalary();
    }
    await _settingsService.setDailyHourlyRate(dateStr, hourlyRate);
    
    // 更新最后保存日期
    _lastSavedDailyDataDate = dateStr;
    
    print('已保存${dateStr}的收入数据和工作时间数据（包含加班）');
  }

  // 添加导出确认对话框
  void _showExportConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出确认'),
        content: const Text('确认导出我的数据？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportData();
            },
            child: const Text('确认导出'),
          ),
        ],
      ),
    );
  }

  // 导出数据功能
  Future<void> _exportData() async {
    try {
      // 请求存储权限
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          _showMessage('需要存储权限才能导出数据');
          return;
        }
      }

      // 显示加载指示器
      _showLoadingDialog();

      // 创建Excel文件
      final excel = Excel.createExcel();
      final sheet = excel['工作数据'];

      // 格式化Excel文件表头
      final headers = ['日期', '上班时间', '实际下班时间', '实际工作时长', '加班时长', '今日搬砖', '今日摸鱼', '实际时薪'];
      for (var i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = headers[i];
      }

      // 获取当前日期
      final now = _timeService.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // 收集历史数据 - 从当前日期倒序收集30天数据
      var rowIndex = 1;
      for (var i = 1; i <= 30; i++) {
        final date = today.subtract(Duration(days: i));
        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        // 获取数据
        final dailyEarnings = _settingsService.getDailyEarnings(dateStr);
        final dailyRestEarnings = _settingsService.getDailyRestEarnings(dateStr);
        final overtimeMinutes = _settingsService.getOvertimeMinutes(dateStr);
        final restMinutes = _settingsService.getDailyRestMinutes(dateStr);
        final dailyWorkMinutes = _settingsService.getDailyWorkMinutes(dateStr);
        
        // 检查是否有数据 - 只有有数据的日期才添加到表格中
        final hasData = dailyEarnings > 0 || 
                        dailyRestEarnings > 0 || 
                        overtimeMinutes > 0 || 
                        restMinutes > 0 ||
                        dailyWorkMinutes > 0;
        
        if (hasData) {
          // 获取每日保存的上班时间、下班时间和时薪
          final dailyStartTime = _settingsService.getDailyStartTime(dateStr);
          final dailyEndTime = _settingsService.getDailyEndTime(dateStr);
          final dailyHourlyRate = _settingsService.getDailyHourlyRate(dateStr);
          
          // 使用存储的工作时长，而不是重新计算
          final workDurationMinutes = dailyWorkMinutes;
          
          // 格式化数据
          final formattedDate = DateFormat('yyyy-MM-dd').format(date);
          final formattedStartTime = '${dailyStartTime.hour.toString().padLeft(2, '0')}:${dailyStartTime.minute.toString().padLeft(2, '0')}';
          final formattedEndTime = '${dailyEndTime.hour.toString().padLeft(2, '0')}:${dailyEndTime.minute.toString().padLeft(2, '0')}';
          final formattedWorkDuration = '${(workDurationMinutes ~/ 60).toString()}小时${(workDurationMinutes % 60).toString()}分钟';
          final formattedOvertimeDuration = '${(overtimeMinutes ~/ 60).toString()}小时${(overtimeMinutes % 60).toString()}分钟';
          
          // 添加行数据
          final rowData = [
            formattedDate,
            formattedStartTime,
            formattedEndTime,
            formattedWorkDuration,
            formattedOvertimeDuration,
            '¥${dailyEarnings.toStringAsFixed(2)}',
            '¥${dailyRestEarnings.toStringAsFixed(2)}',
            '¥${dailyHourlyRate.toStringAsFixed(2)}'
          ];
          
          for (var j = 0; j < rowData.length; j++) {
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIndex)).value = rowData[j];
          }
          rowIndex++;
        }
      }

      // 格式化当前日期用于文件名
      final dateFormatter = DateFormat('yyyyMMdd');
      final formattedDate = dateFormatter.format(now);
      final fileName = 'niuma$formattedDate.xlsx';

      // 获取临时目录用于保存文件
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      
      // 保存Excel文件
      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        
        // 关闭加载对话框
        Navigator.of(context).pop();
        
        // 显示分享对话框，让用户可以选择保存到哪里或分享到其他应用
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: '牛马工作数据导出 $formattedDate',
        );
        
        // 显示导出成功提示
        _showMessage('导出成功，Excel文件已生成');
      } else {
        // 关闭加载对话框
        Navigator.of(context).pop();
        _showMessage('导出失败: 无法生成文件');
      }
    } catch (e) {
      // 关闭加载对话框
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      _showMessage('导出失败: $e');
    }
  }

  // 显示加载对话框
  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 300),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在导出数据...'),
              ],
            ),
          ),
        );
      },
    );
  }

  // 显示消息提示
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // 定期保存摸鱼和加班时长，避免应用被杀死后数据丢失
  void _saveRestStateIfNeeded() {
    final now = _timeService.now();
    // 每60秒保存一次当前摸鱼时长，避免频繁写入
    if (_currentStatus == WorkStatus.resting && now.second == 0) {
      _saveRestDuration();
    }
    
    // 每60秒保存一次当前加班时长，避免频繁写入
    if (_currentStatus == WorkStatus.overtime && now.second == 0) {
      _saveOvertimeDuration();
    }
  }

  // 保存摸鱼时长到持久化存储
  Future<void> _saveRestDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _timeService.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    // 只保存当前摸鱼累计时长（毫秒级精度）
    await prefs.setInt(_lastRestDurationKey, _restDuration.inMilliseconds);
    
    // 同时以分钟精度更新每日摸鱼时长（用于历史统计）
    await _settingsService.setDailyRestMinutes(dateStr, _restDuration.inMinutes);
  }
  
  // 保存加班时长到持久化存储
  Future<void> _saveOvertimeDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _timeService.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    // 保存当前加班累计时长（毫秒级精度）
    await prefs.setInt(_lastOvertimeDurationKey, _overtimeDuration.inMilliseconds);
    
    // 同时以分钟精度更新每日加班时长（用于历史统计）
    await _settingsService.setOvertimeMinutes(dateStr, _overtimeDuration.inMinutes);
    
    print('已保存加班时长(毫秒): ${_overtimeDuration.inMilliseconds}, 分钟: ${_overtimeDuration.inMinutes}');
  }

  // 恢复上次的时长数据
  Future<void> _restoreRestState() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 获取当前日期字符串
    final now = _timeService.now();
    final todayDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    // 检查今天是否是工作日，是否到达上班时间
    final isHoliday = _holidayService.isHoliday(now);
    final isSpecialWorkDay = _holidayService.isWorkday(now);
    final isWeekday = now.weekday <= 5; // 1-5 对应周一至周五
    final isWorkDay = isSpecialWorkDay || (!isHoliday && isWeekday);
    
    // 获取上次重置计时器的日期
    final lastResetDate = prefs.getString(_lastTimerResetDateKey);

    // 判断是否需要重置计时器
    // 如果今天是工作日，且正好是上班时间，且今天还未重置过，则重置计时器
    if (isWorkDay && _isAtStartTime(now) && lastResetDate != todayDateStr) {
      print('应用启动时检测到上班时间，准备重置计时器...');
      await _checkAndResetAllTimers(todayDateStr);
      print('应用启动时重置计时器完成');
    }
    // 如果今天已经重置过，则使用重置后的数据（应该都是0）
    else if (lastResetDate == todayDateStr) {
      print('今天已经重置过计时器，使用重置后的数据');
      _lastRestDuration = Duration.zero;
      _restDuration = Duration.zero;
      _lastOvertimeDuration = Duration.zero;
      _overtimeDuration = Duration.zero;
    }
    // 否则使用保存的数据
    else {
      print('今天还未重置计时器，恢复保存的数据');
      
      // 检查加班日期是否为今天
      final lastOvertimeDate = prefs.getString(_lastOvertimeDateKey);
      if (lastOvertimeDate != null && lastOvertimeDate != todayDateStr) {
        // 上次加班日期不是今天，重置加班数据
        _lastOvertimeDuration = Duration.zero;
        _overtimeDuration = Duration.zero;
        await prefs.setInt(_lastOvertimeDurationKey, 0);
        print('应用启动时重置加班时长 - 加班日期不是今天');
      } else {
        // 上次加班日期是今天，恢复加班数据
        final lastOvertimeDurationMillis = prefs.getInt(_lastOvertimeDurationKey) ?? 0;
        _lastOvertimeDuration = Duration(milliseconds: lastOvertimeDurationMillis);
        _overtimeDuration = _lastOvertimeDuration;
      }
      
      // 恢复摸鱼时长
      final lastRestDurationMillis = prefs.getInt(_lastRestDurationKey) ?? 0;
      _lastRestDuration = Duration(milliseconds: lastRestDurationMillis);
      _restDuration = _lastRestDuration;
    }
    
    // 清除状态标记
    _isManualResting = false;
    _restStartTime = null;
    _isManualOvertime = false;
    _overtimeStartTime = null;
    
    // 保存更新后的状态，确保状态被重置
    await prefs.setBool(_isRestingKey, false);
    await prefs.remove(_restStartTimeKey);
    await prefs.setBool(_isOvertimeKey, false);
    await prefs.remove(_overtimeStartTimeKey);
    
    // 根据当前时间判断是工作中还是下班中
    final isWorkTime = _isExactlyWithinWorkTime(now);
    
    // 在下一帧设置状态，避免在initState中调用setState
    Future.microtask(() {
      if (mounted) {
        setState(() {
          if (isWorkDay && isWorkTime) {
            _currentStatus = WorkStatus.working; // 工作日上班时间 -> 搬砖中
          } else {
            _currentStatus = WorkStatus.offWork; // 非工作时间 -> 下班中
          }
          
          // 设置初始时薪
          _currentRate.value = _settingsService.getHourlySalary();
        });
      }
    });
  }

  // 格式化金额的辅助方法
  String _formatAmount(double amount) {
    // 如果数据隐藏状态为true，则返回隐藏的金额显示
    if (_isDataHidden) {
      return '¥*****.**';
    }
    
    // 处理负数情况
    if (amount < 0) return '¥0.00';
    
    final formattedAmount = amount.toStringAsFixed(2);
    final parts = formattedAmount.split('.');
    final wholePart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    final decimalPart = parts[1];
    return '¥$wholePart.$decimalPart';
  }

  // 添加检查和重置所有计时器的方法
  Future<void> _checkAndResetAllTimers(String todayDateStr) async {
    final now = _timeService.now();
    
    print('执行重置计时器检查 - 当前时间: ${now.hour}:${now.minute}:${now.second}，上班时间: ${_startTime.hour}:${_startTime.minute}:00');
    
    final prefs = await SharedPreferences.getInstance();
    final lastResetDate = prefs.getString(_lastTimerResetDateKey);
    
    // 如果今天已经重置过，则不再重置
    if (lastResetDate == todayDateStr) {
      print('今天(${todayDateStr})已经重置过计时器，跳过重置');
      return;
    }
    
    // 计算昨天的日期字符串，用于保存历史数据
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    
    print('开始重置计时器 - 新的一天开始了');
    
    // 保存昨天的数据到历史记录
    await _saveDataToHistory(yesterdayStr);
    
    // 重置摸鱼时长
    _lastRestDuration = Duration.zero;
    _restDuration = Duration.zero;
    
    // 重置加班时长
    _lastOvertimeDuration = Duration.zero;
    _overtimeDuration = Duration.zero;
    
    // 保存重置后的时长
    await prefs.setInt(_lastRestDurationKey, 0);
    await prefs.setInt(_lastOvertimeDurationKey, 0);
    
    // 清除当天所有相关数据（确保不会从持久化存储中恢复）
    // 今日摸鱼相关
    await _settingsService.setDailyRestMinutes(todayDateStr, 0);
    await _settingsService.setDailyRestEarnings(todayDateStr, 0);
    
    // 今日加班相关
    await _settingsService.setOvertimeMinutes(todayDateStr, 0);
    
    // 今日搬砖相关（确保calculateTodayEarnings重新计算）
    await _settingsService.setDailyEarnings(todayDateStr, 0);
    
    // 今日时薪相关 - 重置为标准时薪，而不是0
    final standardHourlyRate = _settingsService.getHourlySalary();
    await _settingsService.setDailyHourlyRate(todayDateStr, standardHourlyRate);
    
    // 工作时长相关
    await _settingsService.setDailyWorkMinutes(todayDateStr, 0);
    
    // 记录本次重置的日期
    await prefs.setString(_lastTimerResetDateKey, todayDateStr);
    
    // 清除开始时间
    _restStartTime = null;
    _overtimeStartTime = null;
    
    print('已重置所有计时器数据 - 摸鱼时长和加班时长已清零');
    
    // 强制更新UI
    setState(() {
      // 确保重置UI显示
      if (_currentStatus == WorkStatus.resting) {
        _currentStatus = WorkStatus.working;
        _isManualResting = false;
      } else if (_currentStatus == WorkStatus.overtime) {
        _currentStatus = WorkStatus.offWork;
        _isManualOvertime = false;
        _stopHighFrequencyHourlyRateUpdate();
      }
      
      // 立即刷新今日数据
      _todayEarnings.value = 0;
      _restEarnings.value = 0;
      _currentRate.value = standardHourlyRate; // 使用标准时薪
    });
    
    // 显示重置通知
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('新的工作日开始了，计时器已重置！'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    
    print('上班时间到达：已重置所有计时器和今日数据');
  }

  // 将当前数据保存为历史记录
  Future<void> _saveDataToHistory(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final now = _timeService.now();
    
    // 1. 获取当前数据
    final currentRestDuration = _restDuration;
    final currentOvertimeDuration = _overtimeDuration;
    
    // 获取当天累计的数据
    final todayEarnings = _todayEarnings.value;
    final restEarnings = _restEarnings.value;
    final hourlyRate = _currentRate.value;
    
    print('保存昨天($dateStr)数据到历史记录 - 摸鱼:${currentRestDuration.inMinutes}分钟, 加班:${currentOvertimeDuration.inMinutes}分钟, 收入:$todayEarnings');
    
    // 2. 将当前数据保存到历史记录中
    
    // 保存摸鱼数据
    if (currentRestDuration.inMinutes > 0) {
      await _settingsService.setDailyRestMinutes(dateStr, currentRestDuration.inMinutes);
      await _settingsService.setDailyRestEarnings(dateStr, restEarnings);
    }
    
    // 保存加班数据
    if (currentOvertimeDuration.inMinutes > 0) {
      await _settingsService.setOvertimeMinutes(dateStr, currentOvertimeDuration.inMinutes);
    }
    
    // 保存今日收入
    if (todayEarnings > 0) {
      await _settingsService.setDailyEarnings(dateStr, todayEarnings);
    }
    
    // 保存今日时薪
    if (hourlyRate > 0) {
      await _settingsService.setDailyHourlyRate(dateStr, hourlyRate);
    }
    
    // 保存工作时长（根据calculateTodayEarnings计算）
    final workStartDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _startTime.hour,
      _startTime.minute,
    );
    
    final workEndDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _endTime.hour,
      _endTime.minute,
    );
    
    // 计算标准工作时长
    final standardWorkMinutes = workEndDateTime.difference(workStartDateTime).inMinutes;
    
    // 保存工作时长（标准工作时长 + 加班时长）
    await _settingsService.setDailyWorkMinutes(dateStr, standardWorkMinutes + currentOvertimeDuration.inMinutes);
  }

  // 检查今天是否是新的工作日，需要重置加班时长
  Future<void> _checkAndResetOvertimeDuration(bool isWorkDay, bool isWorkTime, String todayDateStr) async {
    if (!isWorkDay || !isWorkTime) return;
    
    final prefs = await SharedPreferences.getInstance();
    final lastOvertimeDate = prefs.getString(_lastOvertimeDateKey);

    // 如果当前是工作日的上班时间，且上次加班日期与今天不同，则重置加班时长
    if (lastOvertimeDate != null && lastOvertimeDate != todayDateStr) {
      // 重置加班时长
      _lastOvertimeDuration = Duration.zero;
      _overtimeDuration = Duration.zero;
      
      // 保存重置后的加班时长
      await prefs.setInt(_lastOvertimeDurationKey, 0);
      
      // 更新UI
      setState(() {});
      
      print('已重置加班时长 - 新的一天开始');
    }
  }

  // 更精确地判断是否到达或超过下班时间，精确到秒
  bool _isExactlyAtOrPastEndTime(DateTime now) {
    // 创建表示今天下班时间的完整DateTime对象
    final workEndDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _endTime.hour,
      _endTime.minute,
    );
    
    // 如果当前时间恰好等于下班时间，打印日志
    if (now.hour == _endTime.hour && now.minute == _endTime.minute && now.second < 10) {
      print('下班时间点精确匹配: 当前时间=${now.hour}:${now.minute}:${now.second}, 下班时间=${_endTime.hour}:${_endTime.minute}:00');
    }
    
    // 精确到秒比较，只要到达或超过下班时间，就返回true
    bool result = now.isAtSameMomentAs(workEndDateTime) || now.isAfter(workEndDateTime);
    
    // 如果状态刚刚切换，记录日志
    if (result && now.hour == _endTime.hour && now.minute == _endTime.minute && now.second < 10) {
      print('状态将切换为下班: 当前=${now.toString()}, 下班时间=${workEndDateTime.toString()}');
    }
    
    return result;
  }

  // 精确到秒判断是否在工作时间内
  bool _isExactlyWithinWorkTime(DateTime now) {
    // 创建表示今天上班和下班时间的完整DateTime对象
    final workStartDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _startTime.hour,
      _startTime.minute,
    );
    
    final workEndDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _endTime.hour,
      _endTime.minute,
    );
    
    // 精确到秒比较，检查当前时间是否在工作时间内
    return (now.isAfter(workStartDateTime) || now.isAtSameMomentAs(workStartDateTime)) && 
           now.isBefore(workEndDateTime);
  }
}

// 重新创建实时收入显示卡片
class RealtimeEarningsCard extends StatefulWidget {
  final String title;
  final double Function() amountCalculator;
  final bool shouldGrayOut;
  final TimeService timeService;
  final bool isDataHidden;
  final Duration refreshInterval;

  const RealtimeEarningsCard({
    Key? key,
    required this.title,
    required this.amountCalculator,
    this.shouldGrayOut = false,
    required this.timeService,
    required this.isDataHidden,
    this.refreshInterval = const Duration(seconds: 1),
  }) : super(key: key);

  @override
  State<RealtimeEarningsCard> createState() => _RealtimeEarningsCardState();
}

class _RealtimeEarningsCardState extends State<RealtimeEarningsCard> {
  late Timer _updateTimer;
  double _amount = 0.0;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    
    // 初始化计算金额
    _calculateAmount();
    
    // 设置定时更新
    _updateTimer = Timer.periodic(widget.refreshInterval, (timer) {
      if (mounted) {
        _calculateAmount();
      }
    });
  }

  @override
  void dispose() {
    _updateTimer.cancel();
    super.dispose();
  }

  // 安全地计算金额
  void _calculateAmount() {
    try {
      setState(() {
        _amount = widget.amountCalculator();
        _hasError = false;
        _errorMessage = '';
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = '计算错误: ${e.toString()}';
        // 保持上一次的有效金额
      });
      print('RealtimeEarningsCard 计算错误: $e');
    }
  }

  // 格式化金额显示
  String _formatAmount(double amount) {
    // 处理负数情况
    if (amount < 0) return '¥0.00';
    
    // 将金额转换为两位小数的字符串
    final wholePart = amount.floor().toString();
    final decimalPart = ((amount - amount.floor()) * 100).round().toString().padLeft(2, '0');
    
    return '¥$wholePart.$decimalPart';
  }

  @override
  Widget build(BuildContext context) {
    // 下班状态和加班状态时的置灰效果
    final Color backgroundColor = widget.shouldGrayOut ? Colors.grey[100]! : Colors.white;
    final Color textColor = widget.shouldGrayOut ? Colors.grey[500]! : Colors.grey;
    final Color amountColor = widget.shouldGrayOut ? Colors.grey[600]! : 
                             _hasError ? Colors.red : Colors.black87;
    
    // 获取金额文本，根据隐藏状态决定是否显示星号
    final String amountText = widget.isDataHidden ? '¥*****.**' : 
                             _hasError ? '计算中...' : _formatAmount(_amount);
    
    return GestureDetector(
      onTap: _calculateAmount, // 添加点击刷新功能
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              amountText,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
            // 在有错误时显示错误提示
            if (_hasError && !widget.isDataHidden)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '点击刷新',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[300],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 添加放假倒计时卡片组件
class HolidayCountdownCard extends StatefulWidget {
  final TimeService timeService;
  final HolidayService holidayService;
  final bool shouldGrayOut;

  const HolidayCountdownCard({
    Key? key,
    required this.timeService,
    required this.holidayService,
    this.shouldGrayOut = false,
  }) : super(key: key);

  @override
  State<HolidayCountdownCard> createState() => _HolidayCountdownCardState();
}

class _HolidayCountdownCardState extends State<HolidayCountdownCard> {
  late Map<String, dynamic> _holidayInfo;
  late Timer _updateTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    
    // 初始化节假日信息
    _holidayInfo = widget.holidayService.getNextHoliday(widget.timeService.now());
    
    // 设置每天午夜更新一次
    _setupMidnightUpdate();
  }

  @override
  void dispose() {
    _updateTimer.cancel();
    super.dispose();
  }

  // 设置午夜更新定时器
  void _setupMidnightUpdate() {
    // 计算到明天午夜的时间
    final now = widget.timeService.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final duration = tomorrow.difference(now);
    
    // 设置定时器，到午夜时更新信息
    _updateTimer = Timer(duration, () {
      if (mounted) {
        setState(() {
          _holidayInfo = widget.holidayService.getNextHoliday(widget.timeService.now());
        });
        // 设置下一个午夜更新
        _setupMidnightUpdate();
      }
    });
  }

  // 手动刷新节假日数据
  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _holidayInfo = widget.holidayService.getNextHoliday(widget.timeService.now());
      _isRefreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final holidayName = _holidayInfo['name'] as String;
    final daysRemaining = _holidayInfo['daysRemaining'] as int;
    final formattedDate = _holidayInfo['formattedDate'] as String;
    final weekday = _holidayInfo['weekday'] as String;
    
    // 颜色设置 - 根据是否置灰调整颜色
    final backgroundColor = widget.shouldGrayOut ? Colors.grey[100]! : Colors.white;
    final titleColor = widget.shouldGrayOut ? Colors.grey[500]! : Colors.grey;
    final daysColor = widget.shouldGrayOut ? Colors.grey[600]! : AppTheme.primaryColor;
    final dateColor = widget.shouldGrayOut ? Colors.grey[400]! : Colors.grey.shade500;
    
    return GestureDetector(
      onTap: _refreshData, // 添加点击刷新功能
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 5,
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '距离$holidayName还有',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$daysRemaining',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: daysColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '天',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: daysColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 添加节假日具体日期和星期
                Text(
                  '$formattedDate · $weekday',
                  style: TextStyle(
                    color: dateColor,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            // 刷新按钮
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: _isRefreshing ? null : _refreshData,
                child: _isRefreshing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                      ),
                    )
                  : Icon(
                      Icons.refresh,
                      size: 20,
                      color: widget.shouldGrayOut 
                        ? Colors.grey[400]! 
                        : AppTheme.primaryColor.withOpacity(0.6),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 