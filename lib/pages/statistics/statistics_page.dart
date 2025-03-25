import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/settings_service.dart';
import '../../utils/holiday_service.dart';
import '../../components/statistics/hourly_rate_card.dart'; // 引入新的组件

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  late DateTime _selectedWeekStart;
  late DateTime _selectedWeekEnd;
  late DateTime _currentWeekStart; // 添加当前周开始日期的引用
  final SettingsService _settingsService = SettingsService();
  final HolidayService _holidayService = HolidayService(); // 添加HolidayService实例
  
  // 存储每日时薪数据
  List<HourlyRateData> _hourlyRateData = [];

  @override
  void initState() {
    super.initState();
    _resetToCurrentWeek();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadHourlyRateData();
  }

  // 重置为当前周
  void _resetToCurrentWeek() {
    final now = DateTime.now();
    // 计算本周一的日期（周一作为一周的开始）
    _currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    // 移除时分秒，只保留日期
    _currentWeekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day);
    
    // 设置选择的周为当前周
    _selectedWeekStart = _currentWeekStart;
    // 计算本周日的日期
    _selectedWeekEnd = _selectedWeekStart.add(const Duration(days: 6));
    
    // 加载时薪数据
    _loadHourlyRateData();
  }

  // 加载时薪数据
  void _loadHourlyRateData() {
    _hourlyRateData = [];
    
    // 获取指定周内每一天的数据
    for (int i = 0; i < 7; i++) {
      final date = _selectedWeekStart.add(Duration(days: i));
      final dateStr = _formatDateAsKey(date);
      
      // 判断是否是工作日
      final bool isWorkDay = _holidayService.shouldWork(date);
      
      // 从设置服务获取该日期的时薪
      final storedHourlyRate = _settingsService.getDailyHourlyRate(dateStr);
      final standardHourlyRate = _settingsService.getHourlySalary();
      
      // 检查是否有特定收入记录
      final bool hasEarnings = _settingsService.getDailyEarnings(dateStr) > 0;
      
      // 确定显示的时薪
      double hourlyRate;
      
      if (!isWorkDay) {
        // 非工作日：只有在有实际收入记录时才显示实际时薪，否则显示0
        hourlyRate = hasEarnings ? storedHourlyRate : 0;
      } else {
        // 工作日逻辑不变
        // 判断是否有记录（存储的时薪与标准时薪不同，说明有实际记录）
        final bool hasRecord = storedHourlyRate != standardHourlyRate || 
                               _settingsService.getDailyWorkMinutes(dateStr) > 0 ||
                               hasEarnings;
        
        if (hasRecord) {
          // 有记录，使用存储的实际时薪
          hourlyRate = storedHourlyRate;
        } else {
          // 工作日但没记录，显示额定时薪
          hourlyRate = standardHourlyRate;
        }
      }
      
      // 创建数据对象
      _hourlyRateData.add(HourlyRateData(
        date: date,
        hourlyRate: hourlyRate,
      ));
    }
    
    setState(() {});
  }

  // 格式化日期为键格式（YYYY-MM-DD）
  String _formatDateAsKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 切换到上一周
  void _goToPreviousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
      _selectedWeekEnd = _selectedWeekEnd.subtract(const Duration(days: 7));
      _loadHourlyRateData();
    });
  }

  // 切换到下一周
  void _goToNextWeek() {
    // 只有当选择的周不是当前周时，才允许前进到下一周
    if (_selectedWeekStart.isBefore(_currentWeekStart)) {
      setState(() {
        // 确保不会超过当前周
        final nextWeekStart = _selectedWeekStart.add(const Duration(days: 7));
        if (nextWeekStart.isAfter(_currentWeekStart)) {
          // 如果下一周会超过当前周，直接跳到当前周
          _selectedWeekStart = _currentWeekStart;
        } else {
          _selectedWeekStart = nextWeekStart;
        }
        _selectedWeekEnd = _selectedWeekStart.add(const Duration(days: 6));
        _loadHourlyRateData();
      });
    }
  }

  // 格式化日期为年-月-日的形式
  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // 检查选择的周是否是当前周
  bool _isCurrentWeek() {
    return _selectedWeekStart.isAtSameMomentAs(_currentWeekStart);
  }

  // 添加上周平均时薪计算方法
  double _getLastWeekAverageHourlyRate() {
    // 计算上周开始日期
    final lastWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
    
    // 存储上周的时薪数据
    List<HourlyRateData> lastWeekData = [];
    
    // 获取上周每一天的数据
    for (int i = 0; i < 7; i++) {
      final date = lastWeekStart.add(Duration(days: i));
      final dateStr = _formatDateAsKey(date);
      
      final bool isWorkDay = _holidayService.shouldWork(date);
      final storedHourlyRate = _settingsService.getDailyHourlyRate(dateStr);
      final standardHourlyRate = _settingsService.getHourlySalary();
      final bool hasEarnings = _settingsService.getDailyEarnings(dateStr) > 0;
      
      // 确定显示的时薪（与_loadHourlyRateData逻辑保持一致）
      double hourlyRate;
      
      if (!isWorkDay) {
        hourlyRate = hasEarnings ? storedHourlyRate : 0;
      } else {
        final bool hasRecord = storedHourlyRate != standardHourlyRate || 
                          _settingsService.getDailyWorkMinutes(dateStr) > 0 ||
                          hasEarnings;
        
        if (hasRecord) {
          hourlyRate = storedHourlyRate;
        } else {
          hourlyRate = standardHourlyRate;
        }
      }
      
      lastWeekData.add(HourlyRateData(
        date: date,
        hourlyRate: hourlyRate,
      ));
    }
    
    // 计算上周平均时薪
    double lastWeekAverageHourlyRate = 0;
    int validDataCount = 0;
    
    for (var data in lastWeekData) {
      if (data.hourlyRate > 0) {
        lastWeekAverageHourlyRate += data.hourlyRate;
        validDataCount++;
      }
    }
    
    if (validDataCount > 0) {
      lastWeekAverageHourlyRate = lastWeekAverageHourlyRate / validDataCount;
    }
    
    return lastWeekAverageHourlyRate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
      ),
      body: Column(
        children: [
          // 周选择器
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 上一周按钮
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 18),
                  onPressed: _goToPreviousWeek,
                  tooltip: '上一周',
                ),
                
                // 周日期范围显示
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // 可以在这里添加日期选择器功能
                    },
                    child: Column(
                      children: [
                        Text(
                          '${_formatDate(_selectedWeekStart)} 至 ${_formatDate(_selectedWeekEnd)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '第${_getWeekOfYear(_selectedWeekStart)}周',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                
                // 下一周按钮 - 仅当不是当前周时启用
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 18),
                  onPressed: _isCurrentWeek() ? null : _goToNextWeek,
                  tooltip: '下一周',
                  // 当前周时禁用按钮的视觉样式
                  color: _isCurrentWeek() ? Colors.grey[400] : null,
                ),
                
                // 回到本周按钮，仅在非本周时显示
                if (!_isCurrentWeek())
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _resetToCurrentWeek();
                      });
                    },
                    child: const Text('本周'),
                  ),
              ],
            ),
          ),
          
          // 统计内容区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 使用新的时薪卡片组件
                  HourlyRateCard(
                    hourlyRateData: _hourlyRateData,
                    lastWeekAverageHourlyRate: _getLastWeekAverageHourlyRate(),
                    standardHourlyRate: _settingsService.getHourlySalary(),
                    onSwipeLeft: !_isCurrentWeek() ? _goToNextWeek : null,
                    onSwipeRight: _goToPreviousWeek,
                    canSwipeLeft: !_isCurrentWeek(),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 其他统计数据...
                  Center(
                    child: Text('${_formatDate(_selectedWeekStart)} - ${_formatDate(_selectedWeekEnd)}的统计数据'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // 获取给定日期是一年中的第几周
  int _getWeekOfYear(DateTime date) {
    // 计算一年的第一天
    final firstDayOfYear = DateTime(date.year, 1, 1);
    // 计算第一天是星期几（0是星期日，1是星期一，...）
    final dayOfWeek = firstDayOfYear.weekday;
    // 第一周可能不完整，计算偏移
    final daysOffset = dayOfWeek <= DateTime.thursday ? dayOfWeek - 1 : 8 - dayOfWeek;
    // 计算当前日期是一年中的第几天
    final dayOfYear = int.parse(DateFormat('D').format(date));
    // 计算出周数
    return ((dayOfYear + daysOffset - 1) / 7).ceil();
  }
} 