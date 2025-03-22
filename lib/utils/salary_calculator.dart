import 'package:flutter/material.dart';
import 'time_service.dart';
import 'settings_service.dart';
import 'holiday_service.dart';

class SalaryCalculator {
  static double calculateTodayEarnings({
    required DateTime currentTime,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required String salaryType,
    required double salary,
  }) {
    // 获取今天的上班和下班时间
    final now = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
      currentTime.hour,
      currentTime.minute,
      currentTime.second,
      currentTime.millisecond, // 添加毫秒精度
    );
    
    // 检查今天是否是工作日
    final holidayService = HolidayService();
    final settingsService = SettingsService();
    
    // 使用shouldWork方法判断是否是工作日
    final isWorkDay = holidayService.shouldWork(now);
    
    // 获取当天日期字符串，用于检查是否有保存的收入数据
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final savedEarnings = settingsService.getDailyEarnings(dateStr);
    
    // 检查是否有保存的今日数据
    if (savedEarnings != null && savedEarnings > 0) {
      // 如果有保存的收入数据且大于0，使用保存的数据
      return savedEarnings;
    }
    
    // 获取昨天的日期
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final yesterdayEarnings = settingsService.getDailyEarnings(yesterdayStr);
    
    // 如果今天不是工作日，或者是工作日但还未到上班时间，使用昨天的数据
    if (!isWorkDay || (isWorkDay && now.isBefore(DateTime(
      now.year,
      now.month,
      now.day,
      startTime.hour,
      startTime.minute,
    )))) {
      // 如果有昨天的收入数据且大于0，使用昨天的数据
      if (yesterdayEarnings != null && yesterdayEarnings > 0) {
        return yesterdayEarnings;
      }
      
      // 如果没有昨天的数据，使用标准日薪
      final standardHoursPerDay = 8.0;
      return settingsService.getHourlySalary() * standardHoursPerDay;
    }
    
    final workStart = DateTime(
      now.year,
      now.month,
      now.day,
      startTime.hour,
      startTime.minute,
    );
    
    final workEnd = DateTime(
      now.year,
      now.month,
      now.day,
      endTime.hour,
      endTime.minute,
    );
    
    // 如果已经超过下班时间，使用下班时间计算
    final effectiveCurrentTime = now.isAfter(workEnd) ? workEnd : now;
    
    // 计算工作时长（使用毫秒级精度）
    final workedMilliseconds = effectiveCurrentTime.difference(workStart).inMilliseconds;
    final totalWorkMilliseconds = workEnd.difference(workStart).inMilliseconds;
    final workedHours = workedMilliseconds / (1000 * 60 * 60);
    
    // 获取预计算的日薪和时薪
    final dailySalary = settingsService.getDailySalary();
    final hourlySalary = settingsService.getHourlySalary();

    switch (salaryType) {
      case '月薪':
      case '年薪':
      case '日薪':
        // 使用预计算的日薪 * 当天工作比例（使用毫秒级精度）
        return (workedMilliseconds / totalWorkMilliseconds) * dailySalary;
      case '时薪':
        // 使用预计算的时薪 * 工作小时数
        return workedHours * hourlySalary;
      default:
        return 0;
    }
  }

  static double calculateRestEarnings({
    required Duration restDuration,
    required String salaryType,
    required double salary,
  }) {
    // 获取预计算的时薪
    final settingsService = SettingsService();
    final hourlySalary = settingsService.getHourlySalary();
    
    // 转换摸鱼时长为小时（使用毫秒级精度）
    final restHours = restDuration.inMilliseconds / (1000 * 60 * 60);

    switch (salaryType) {
      case '月薪':
      case '年薪':
      case '日薪':
        // 使用预计算的时薪 * 摸鱼小时数
        return restHours * hourlySalary;
      case '时薪':
        // 使用用户输入的时薪 * 摸鱼小时数
        return restHours * salary;
      default:
        return 0;
    }
  }

  static double calculateYearToDateEarnings({
    required DateTime currentTime,
    required String salaryType,
    required double salary,
  }) {
    final holidayService = HolidayService();
    final settingsService = SettingsService();
    
    // 获取2025年1月1日
    final startDate = DateTime(2025, 1, 1);
    
    // 获取昨天的日期（不包含今天）
    final yesterday = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    ).subtract(const Duration(days: 1));
    
    // 计算从1月1日到昨天的工作日天数
    int actualWorkDays = 0;
    for (DateTime date = startDate;
         date.isBefore(yesterday) || date.isAtSameMomentAs(yesterday);
         date = date.add(const Duration(days: 1))) {
      // 使用shouldWork方法判断是否是工作日
      if (holidayService.shouldWork(date)) {
        actualWorkDays++;
      }
    }
    
    // 计算历史收入（不包括今天）
    double historicalEarnings;
    if (salaryType == '日薪') {
      // 使用用户输入的日薪
      historicalEarnings = actualWorkDays * salary;
    } else {
      // 使用预计算的日薪
      final dailySalary = settingsService.getDailySalary();
      historicalEarnings = actualWorkDays * dailySalary;
    }
    
    // 直接返回历史收入，不包括今日收入
    return historicalEarnings;
  }

  static double calculateWeekRestEarnings({
    required DateTime currentTime,
    required Duration todayRestDuration,
    required String salaryType,
    required double salary,
  }) {
    final settingsService = SettingsService();
    
    // 获取本周一的日期
    final now = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    );
    final daysFromMonday = now.weekday - DateTime.monday;
    final monday = now.subtract(Duration(days: daysFromMonday));
    
    // 获取昨天的日期（不包括今天）
    final yesterday = now.subtract(const Duration(days: 1));
    
    // 计算从本周一到昨天的摸鱼收入（不包括今天）
    double historicalRestEarnings = 0.0;
    for (DateTime date = monday;
         date.isBefore(yesterday) || date.isAtSameMomentAs(yesterday);
         date = date.add(const Duration(days: 1))) {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final dailyRestMinutes = settingsService.getDailyRestMinutes(dateStr);
      final dailyRestHours = dailyRestMinutes / 60.0;
      
      if (salaryType == '时薪') {
        historicalRestEarnings += dailyRestHours * salary;
      } else {
        final hourlySalary = settingsService.getHourlySalary();
        historicalRestEarnings += dailyRestHours * hourlySalary;
      }
    }
    
    // 直接返回历史摸鱼收入，不包括今日
    return historicalRestEarnings;
  }
} 