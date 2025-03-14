import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // 添加设置变更通知
  final ValueNotifier<bool> settingsChangedNotifier = ValueNotifier<bool>(false);

  // 常量定义
  static const String _startTimeHourKey = 'start_time_hour';
  static const String _startTimeMinuteKey = 'start_time_minute';
  static const String _endTimeHourKey = 'end_time_hour';
  static const String _endTimeMinuteKey = 'end_time_minute';
  static const String _salaryTypeKey = 'salary_type';
  static const String _salaryKey = 'salary';
  static const String _dailySalaryKey = 'daily_salary';
  static const String _hourlySalaryKey = 'hourly_salary';
  static const String _overtimeMinutesKey = 'overtime_minutes';

  // 工作时长相关常量
  static const double standardWorkHoursPerDay = 8.0;  // 标准工作时长（小时）
  static const double standardWorkDaysPerMonth = 21.75;  // 每月平均工作天数
  static const double standardWorkHoursPerMonth = standardWorkHoursPerDay * standardWorkDaysPerMonth;  // 每月标准工作时长

  SharedPreferences? _prefsInstance;

  Future<SharedPreferences> get _prefs async {
    _prefsInstance ??= await SharedPreferences.getInstance();
    return _prefsInstance!;
  }

  // 计算并保存日薪和时薪
  Future<void> _updateDerivedSalaries() async {
    final prefs = await _prefs;
    final salaryType = getSalaryType();
    final salary = getSalary();

    // 计算日薪
    double dailySalary;
    if (salaryType == '月薪') {
      dailySalary = salary / standardWorkDaysPerMonth;
    } else if (salaryType == '时薪') {
      dailySalary = salary * standardWorkHoursPerDay;
    } else {
      dailySalary = salary;
    }

    // 计算时薪
    double hourlySalary;
    if (salaryType == '月薪') {
      hourlySalary = salary / standardWorkHoursPerMonth;
    } else if (salaryType == '日薪') {
      hourlySalary = salary / standardWorkHoursPerDay;
    } else {
      hourlySalary = salary;
    }

    // 保存计算结果
    await prefs.setDouble(_dailySalaryKey, dailySalary);
    await prefs.setDouble(_hourlySalaryKey, hourlySalary);
  }

  // 获取日薪
  double getDailySalary() {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return 0.0;
    }
    return prefs.getDouble(_dailySalaryKey) ?? 0.0;
  }

  // 获取时薪
  double getHourlySalary() {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return 0.0;
    }
    return prefs.getDouble(_hourlySalaryKey) ?? 0.0;
  }

  // 获取上班时间
  TimeOfDay getStartTime() {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
    return TimeOfDay(
      hour: prefs.getInt(_startTimeHourKey) ?? 8,
      minute: prefs.getInt(_startTimeMinuteKey) ?? 0,
    );
  }

  // 保存上班时间
  Future<void> setStartTime(TimeOfDay time) async {
    final prefs = await _prefs;
    await prefs.setInt(_startTimeHourKey, time.hour);
    await prefs.setInt(_startTimeMinuteKey, time.minute);
    await _updateDerivedSalaries();
    _notifySettingsChanged();
  }

  // 获取下班时间
  TimeOfDay getEndTime() {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return const TimeOfDay(hour: 18, minute: 0);
    }
    return TimeOfDay(
      hour: prefs.getInt(_endTimeHourKey) ?? 18,
      minute: prefs.getInt(_endTimeMinuteKey) ?? 0,
    );
  }

  // 保存下班时间
  Future<void> setEndTime(TimeOfDay time) async {
    final prefs = await _prefs;
    await prefs.setInt(_endTimeHourKey, time.hour);
    await prefs.setInt(_endTimeMinuteKey, time.minute);
    await _updateDerivedSalaries();
    _notifySettingsChanged();
  }

  // 获取薪资类型
  String getSalaryType() {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return '月薪';
    }
    return prefs.getString(_salaryTypeKey) ?? '月薪';
  }

  // 保存薪资类型
  Future<void> setSalaryType(String type) async {
    final prefs = await _prefs;
    await prefs.setString(_salaryTypeKey, type);
    await _updateDerivedSalaries();
    _notifySettingsChanged();
  }

  // 获取薪资金额
  double getSalary() {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return 100000;
    }
    return prefs.getDouble(_salaryKey) ?? 100000;
  }

  // 保存薪资金额
  Future<void> setSalary(double salary) async {
    final prefs = await _prefs;
    await prefs.setDouble(_salaryKey, salary);
    await _updateDerivedSalaries();
    _notifySettingsChanged();
  }

  // 初始化
  Future<void> init() async {
    _prefsInstance = await SharedPreferences.getInstance();
    await _updateDerivedSalaries(); // 初始化时计算一次
  }

  // 通知设置变更
  void _notifySettingsChanged() {
    settingsChangedNotifier.value = !settingsChangedNotifier.value;
  }

  // 获取指定日期的摸鱼分钟数
  int getDailyRestMinutes(String dateStr) {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return 0;
    }
    return prefs.getInt('rest_minutes_$dateStr') ?? 0;
  }

  // 保存指定日期的摸鱼分钟数
  Future<void> setDailyRestMinutes(String dateStr, int minutes) async {
    final prefs = await _prefs;
    await prefs.setInt('rest_minutes_$dateStr', minutes);
  }

  // 获取加班时长（分钟）
  int getOvertimeMinutes(String dateStr) {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return 0;
    }
    return prefs.getInt('${_overtimeMinutesKey}_$dateStr') ?? 0;
  }

  // 保存加班时长（分钟）
  Future<void> setOvertimeMinutes(String dateStr, int minutes) async {
    final prefs = await _prefs;
    await prefs.setInt('${_overtimeMinutesKey}_$dateStr', minutes);
  }

  // 保存今日搬砖收入
  Future<void> setDailyEarnings(String dateStr, double amount) async {
    final prefs = await _prefs;
    await prefs.setDouble('daily_earnings_$dateStr', amount);
  }

  // 获取今日搬砖收入
  double getDailyEarnings(String dateStr) {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return 0.0;
    }
    return prefs.getDouble('daily_earnings_$dateStr') ?? 0.0;
  }

  // 获取今日摸鱼收入
  double getDailyRestEarnings(String dateStr) {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return 0.0;
    }
    return prefs.getDouble('daily_rest_earnings_$dateStr') ?? 0.0;
  }

  // 保存今日摸鱼收入
  Future<void> setDailyRestEarnings(String dateStr, double amount) async {
    final prefs = await _prefs;
    await prefs.setDouble('daily_rest_earnings_$dateStr', amount);
  }

  // 保存每日上班时间
  Future<void> setDailyStartTime(String dateStr, TimeOfDay time) async {
    final prefs = await _prefs;
    await prefs.setInt('daily_start_hour_$dateStr', time.hour);
    await prefs.setInt('daily_start_minute_$dateStr', time.minute);
  }

  // 获取每日上班时间
  TimeOfDay getDailyStartTime(String dateStr) {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
    return TimeOfDay(
      hour: prefs.getInt('daily_start_hour_$dateStr') ?? getStartTime().hour,
      minute: prefs.getInt('daily_start_minute_$dateStr') ?? getStartTime().minute,
    );
  }

  // 保存每日下班时间
  Future<void> setDailyEndTime(String dateStr, TimeOfDay time) async {
    final prefs = await _prefs;
    await prefs.setInt('daily_end_hour_$dateStr', time.hour);
    await prefs.setInt('daily_end_minute_$dateStr', time.minute);
  }

  // 获取每日下班时间
  TimeOfDay getDailyEndTime(String dateStr) {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return const TimeOfDay(hour: 18, minute: 0);
    }
    return TimeOfDay(
      hour: prefs.getInt('daily_end_hour_$dateStr') ?? getEndTime().hour,
      minute: prefs.getInt('daily_end_minute_$dateStr') ?? getEndTime().minute,
    );
  }

  // 保存每日工作时长（分钟）
  Future<void> setDailyWorkMinutes(String dateStr, int minutes) async {
    final prefs = await _prefs;
    await prefs.setInt('daily_work_minutes_$dateStr', minutes);
  }

  // 获取每日工作时长（分钟）
  int getDailyWorkMinutes(String dateStr) {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return 480; // 默认8小时
    }
    return prefs.getInt('daily_work_minutes_$dateStr') ?? 480;
  }

  // 保存每日时薪
  Future<void> setDailyHourlyRate(String dateStr, double rate) async {
    final prefs = await _prefs;
    await prefs.setDouble('daily_hourly_rate_$dateStr', rate);
  }

  // 获取每日时薪
  double getDailyHourlyRate(String dateStr) {
    final prefs = _prefsInstance;
    if (prefs == null) {
      return getHourlySalary();
    }
    return prefs.getDouble('daily_hourly_rate_$dateStr') ?? getHourlySalary();
  }

  // 清理过期的摸鱼数据（可选：保留最近30天的数据）
  Future<void> cleanupOldRestData() async {
    final prefs = await _prefs;
    final now = DateTime.now();
    
    // 需要清理的前缀列表
    final prefixesToClean = [
      'rest_minutes_',
      '${_overtimeMinutesKey}_',
      'daily_earnings_',
      'daily_rest_earnings_',
      'daily_start_hour_',
      'daily_start_minute_',
      'daily_end_hour_',
      'daily_end_minute_',
      'daily_work_minutes_',
      'daily_hourly_rate_'
    ];
    
    // 遍历所有前缀，清理过期数据
    for (final prefix in prefixesToClean) {
      final keys = prefs.getKeys().where((key) => key.startsWith(prefix));
      for (final key in keys) {
        final dateStr = key.substring(prefix.length);
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final date = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
          if (now.difference(date).inDays > 30) {
            await prefs.remove(key);
          }
        }
      }
    }
  }
} 