import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HolidayService {
  static final HolidayService _instance = HolidayService._internal();
  factory HolidayService() => _instance;
  HolidayService._internal();

  // 2025年法定节假日
  final Set<String> _holidays2025 = {
    // 元旦
    '2025-01-01',
    // 春节
    '2025-01-29',
    '2025-01-30',
    '2025-01-31',
    '2025-02-01',
    '2025-02-02',
    '2025-02-03',
    '2025-02-04',
    // 清明节
    '2025-04-05',
    '2025-04-06',
    '2025-04-07',
    // 劳动节
    '2025-05-01',
    '2025-05-02',
    '2025-05-03',
    '2025-05-04',
    '2025-05-05',
    // 端午节
    '2025-06-22',
    '2025-06-23',
    '2025-06-24',
    // 中秋节
    '2025-09-12',
    '2025-09-13',
    '2025-09-14',
    // 国庆节
    '2025-10-01',
    '2025-10-02',
    '2025-10-03',
    '2025-10-04',
    '2025-10-05',
    '2025-10-06',
    '2025-10-07',
  };

  // 2025年调休上班日
  final Set<String> _workdays2025 = {
    // 春节调休
    '2025-02-08',
    '2025-02-09',
    // 劳动节调休
    '2025-04-27',
    '2025-05-11',
    // 端午节调休
    '2025-06-21',
    // 中秋节调休
    '2025-09-07',
    // 国庆节调休
    '2025-09-28',
    '2025-10-12',
  };
  
  // 节假日名称映射
  final Map<String, String> _holidayNames = {
    // 元旦
    '2025-01-01': '元旦',
    // 春节 (取第一天作为代表)
    '2025-01-29': '春节',
    // 清明节
    '2025-04-05': '清明节',
    // 劳动节
    '2025-05-01': '劳动节',
    // 端午节
    '2025-06-22': '端午节',
    // 中秋节
    '2025-09-12': '中秋节',
    // 国庆节
    '2025-10-01': '国庆节',
  };
  
  // 节假日起始日期
  final List<String> _holidayStartDates = [
    '2025-01-01', // 元旦
    '2025-01-29', // 春节
    '2025-04-05', // 清明节
    '2025-05-01', // 劳动节
    '2025-06-22', // 端午节
    '2025-09-12', // 中秋节
    '2025-10-01', // 国庆节
  ];

  bool isHoliday(DateTime date) {
    if (date.year != 2025) return false;
    
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _holidays2025.contains(dateStr);
  }

  bool isWorkday(DateTime date) {
    if (date.year != 2025) return false;
    
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _workdays2025.contains(dateStr);
  }

  bool shouldWork(DateTime date) {
    // 如果是法定节假日，不上班
    if (isHoliday(date)) return false;
    
    // 如果是调休工作日，需要上班
    if (isWorkday(date)) return true;
    
    // 周一至周五是工作日，周末不上班
    return date.weekday <= 5;
  }
  
  // 获取距离当前日期最近的下一个节假日信息
  Map<String, dynamic> getNextHoliday(DateTime currentDate) {
    // 格式化当前日期为yyyy-MM-dd格式
    final formatter = DateFormat('yyyy-MM-dd');
    final formattedCurrentDate = formatter.format(currentDate);
    
    String closestHolidayDate = '';
    String holidayName = '';
    int daysRemaining = 0;
    
    // 查找最近的节假日
    for (var i = 0; i < _holidayStartDates.length; i++) {
      final holidayDateStr = _holidayStartDates[i];
      
      // 检查当前日期与节假日日期的先后顺序
      if (formattedCurrentDate.compareTo(holidayDateStr) <= 0) {
        // 找到最近的未来节假日
        closestHolidayDate = holidayDateStr;
        holidayName = _holidayNames[holidayDateStr] ?? '未知假期';
        
        // 计算剩余天数
        final holidayDate = formatter.parse(holidayDateStr);
        daysRemaining = holidayDate.difference(currentDate).inDays;
        
        break;
      }
    }
    
    // 如果没有找到今年剩余的节假日，则查找下一年的第一个节假日
    if (closestHolidayDate.isEmpty) {
      // 获取下一年的第一个节假日（通常是元旦）
      final nextYear = currentDate.year + 1;
      final nextYearFirstHoliday = '$nextYear-01-01';
      holidayName = '元旦';
      closestHolidayDate = nextYearFirstHoliday;
      
      // 计算剩余天数
      final holidayDate = formatter.parse(nextYearFirstHoliday);
      daysRemaining = holidayDate.difference(currentDate).inDays;
    }
    
    // 解析日期以获取格式化显示
    final holidayDate = formatter.parse(closestHolidayDate);
    
    // 使用纯数字格式显示月日，不使用中文字符
    final numericDateFormat = DateFormat('MM-dd');
    final formattedDate = numericDateFormat.format(holidayDate);
    
    // 获取星期几 - 使用周几格式
    final weekday = _getWeekdayName(holidayDate.weekday);
    
    return {
      'name': holidayName,
      'date': closestHolidayDate,
      'formattedDate': formattedDate,
      'weekday': weekday,
      'daysRemaining': daysRemaining,
    };
  }
  
  // 获取星期几的中文名称 - 改为周几格式
  String _getWeekdayName(int weekday) {
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[weekday - 1];
  }
} 