import 'package:flutter/material.dart';

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
} 