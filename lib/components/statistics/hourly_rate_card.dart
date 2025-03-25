import 'package:flutter/material.dart';
import '../../utils/settings_service.dart';

// 时薪数据模型
class HourlyRateData {
  final DateTime date;
  final double hourlyRate;
  
  HourlyRateData({
    required this.date,
    required this.hourlyRate,
  });
  
  // 获取星期几的中文表示
  String get weekdayName {
    const List<String> weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    // weekday范围是1-7，其中1表示周一
    return weekdays[date.weekday - 1];
  }
  
  // 判断是否为工作日 - 此方法现在不使用，但保留以防其他地方引用
  bool get isWorkday {
    // 使用HolidayService判断更准确，但由于这是一个getter，不能直接调用HolidayService
    // 这里保留简单逻辑作为后备
    return date.weekday >= 1 && date.weekday <= 5;
  }
}

// 时薪柱状图组件
class HourlyRateChart extends StatefulWidget {
  final List<HourlyRateData> data;
  final double maxHourlyRate;
  final VoidCallback? onSwipeLeft; // 添加左滑回调
  final VoidCallback? onSwipeRight; // 添加右滑回调
  final bool canSwipeLeft; // 是否可以左滑（是否不是当前周）
  
  const HourlyRateChart({
    super.key,
    required this.data,
    required this.maxHourlyRate,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.canSwipeLeft = true,
  });

  @override
  State<HourlyRateChart> createState() => _HourlyRateChartState();
}

class _HourlyRateChartState extends State<HourlyRateChart> {
  // 用于滑动手势的变量
  double _dragStartX = 0;
  double _dragDistance = 0;
  bool _isDragging = false;
  
  // 视觉反馈变量 - 重命名变量使其更直观
  bool _showLeftArrow = false;  // 左侧向左箭头
  bool _showRightArrow = false; // 右侧向右箭头
  
  // 重置视觉反馈的计时器
  void _resetFeedback() {
    if (_showLeftArrow || _showRightArrow) {
      setState(() {
        _showLeftArrow = false;
        _showRightArrow = false;
      });
    }
  }
  
  // 计算平均时薪
  double get averageHourlyRate {
    if (widget.data.isEmpty) return 0;
    
    double sum = 0;
    int count = 0;
    
    for (var item in widget.data) {
      if (item.hourlyRate > 0) {
        sum += item.hourlyRate;
        count++;
      }
    }
    
    return count > 0 ? sum / count : 0;
  }
  
  @override
  Widget build(BuildContext context) {
    // 计算平均时薪的比例
    final double averageRatio = averageHourlyRate > 0 
        ? averageHourlyRate / widget.maxHourlyRate 
        : 0;
    
    // 最小滑动距离，超过这个距离才触发切换
    final double minSwipeDistance = MediaQuery.of(context).size.width * 0.15;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 整体左对齐
      children: [
        // 柱状图绘制区域 - 增强手势检测
        Expanded(
          child: Stack(
            children: [
              // 手势检测区域 - 占满整个区域，确保任何地方滑动都能检测到
              Positioned.fill(
                child: GestureDetector(
                  // 开始拖动
                  onHorizontalDragStart: (details) {
                    _dragStartX = details.localPosition.dx;
                    _dragDistance = 0;
                    _isDragging = true;
                    _resetFeedback();
                  },
                  
                  // 拖动更新
                  onHorizontalDragUpdate: (details) {
                    if (_isDragging) {
                      setState(() {
                        _dragDistance = details.localPosition.dx - _dragStartX;
                        
                        // 根据拖动方向和距离显示视觉反馈
                        if (_dragDistance < -minSwipeDistance && widget.canSwipeLeft) {
                          // 向左滑动，显示左侧向左箭头
                          _showLeftArrow = true;
                          _showRightArrow = false;
                        } else if (_dragDistance > minSwipeDistance) {
                          // 向右滑动，显示右侧向右箭头
                          _showRightArrow = true;
                          _showLeftArrow = false;
                        } else {
                          _showLeftArrow = false;
                          _showRightArrow = false;
                        }
                      });
                    }
                  },
                  
                  // 拖动结束
                  onHorizontalDragEnd: (details) {
                    // 基于拖动距离而不是速度来判断滑动方向
                    if (_isDragging) {
                      if (_dragDistance < -minSwipeDistance && widget.canSwipeLeft && widget.onSwipeLeft != null) {
                        // 向左滑动，切换到下一周
                        widget.onSwipeLeft!();
                      } else if (_dragDistance > minSwipeDistance && widget.onSwipeRight != null) {
                        // 向右滑动，切换到上一周
                        widget.onSwipeRight!();
                      }
                      
                      // 重置状态
                      _isDragging = false;
                      
                      // 300毫秒后重置视觉反馈
                      Future.delayed(const Duration(milliseconds: 300), _resetFeedback);
                    }
                  },
                  
                  // 添加一个透明的容器，确保整个区域都能响应手势
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              
              // 左右滑动提示 - 半透明箭头指示方向
              if (_showLeftArrow) // 左侧向左箭头
                Positioned(
                  left: 20, // 左侧
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(
                      Icons.arrow_back_ios, // 向左的箭头
                      size: 40,
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                    ),
                  ),
                ),
              
              if (_showRightArrow) // 右侧向右箭头
                Positioned(
                  right: 20, // 右侧
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(
                      Icons.arrow_forward_ios, // 向右的箭头
                      size: 40,
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                    ),
                  ),
                ),
              
              // 柱状图区域
              Positioned.fill(
                child: IgnorePointer( // 防止柱状图拦截手势
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24), // 为右侧平均文本预留空间
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(widget.data.length, (index) {
                        final item = widget.data[index];
                        
                        // 柱状图高度比例，最大为1
                        final double barHeightRatio = item.hourlyRate > 0 
                            ? item.hourlyRate / widget.maxHourlyRate 
                            : 0;
                        
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _buildBar(context, item, barHeightRatio),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
              
              // 只绘制平均值虚线，不包含文本标签
              if (averageRatio > 0)
                Positioned(
                  left: 0,
                  // 右侧留出更多空间给竖向文本
                  right: 24,
                  // 与平均文字的中心对齐
                  bottom: averageRatio * 150, 
                  child: IgnorePointer( // 防止虚线拦截手势
                    child: Container(
                      height: 1,
                      color: Colors.transparent,
                      child: CustomPaint(
                        size: const Size(double.infinity, 1),
                        painter: DashedLinePainter(
                          color: Colors.grey[700]!,
                          dashWidth: 3,
                          dashSpace: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 平均值竖向文本 - 放在绝对右侧，远离所有柱子
                if (averageRatio > 0)
                  Positioned(
                    right: 4,
                    // 让"平均"两字的中间位置与虚线对齐
                    bottom: (averageRatio * 150) - 17,
                    child: IgnorePointer( // 防止文本拦截手势
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '平',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700]!,
                            ),
                          ),
                          const SizedBox(height: 4), // 在两个字之间添加间隔
                          Text(
                            '均',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700]!,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        // 底部标签（周一至周日）
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.start, // 改为左对齐
          children: widget.data.map((item) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                item.weekdayName,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700]!,
                ),
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }
  
  Widget _buildBar(BuildContext context, HourlyRateData item, double heightRatio) {
    // 使用统一的颜色，不再区分工作日和周末
    final barColor = Theme.of(context).primaryColor;
    
    // 获取标准时薪
    final settingsService = SettingsService();
    final standardHourlyRate = settingsService.getHourlySalary();
    final standardRatio = standardHourlyRate / widget.maxHourlyRate;
    
    // 计算标准时薪条的高度
    final standardHeight = standardRatio * 150; // 最大高度为150
    final actualBarHeight = heightRatio * 150; // 紫色柱子的高度

    // 构建时薪文本 - 当有时薪时才显示
    Widget? hourlyRateText = item.hourlyRate > 0
        ? Text(
            '¥${item.hourlyRate.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[700]!,
            ),
          )
        : null;
    
    return SizedBox(
      height: 174, // 150 + 标签和文字的空间
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none, // 允许子元素超出边界
        children: [
          // 标准时薪底部浅灰色柱子
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: standardHeight,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
          ),
          
          // 实际时薪紫色柱子
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: actualBarHeight,
            child: Container(
              decoration: BoxDecoration(
                color: barColor.withOpacity(0.7),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
          ),
          
          // 时薪文本 - 位于紫色柱子顶部上方
          if (hourlyRateText != null)
            Positioned(
              bottom: actualBarHeight + 4, // 紫色柱子顶部上方4像素
              child: hourlyRateText,
            ),
        ],
      ),
    );
  }
}

// 虚线绘制器
class DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  DashedLinePainter({
    required this.color,
    this.dashWidth = 5,
    this.dashSpace = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double startX = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(DashedLinePainter oldDelegate) => 
    color != oldDelegate.color ||
    dashWidth != oldDelegate.dashWidth ||
    dashSpace != oldDelegate.dashSpace;
}

/// 完整的时薪卡片组件
class HourlyRateCard extends StatelessWidget {
  final List<HourlyRateData> hourlyRateData; // 时薪数据
  final double lastWeekAverageHourlyRate; // 上周平均时薪
  final double standardHourlyRate; // 标准时薪
  final VoidCallback? onSwipeLeft; // 左滑回调
  final VoidCallback? onSwipeRight; // 右滑回调
  final bool canSwipeLeft; // 是否可以左滑

  const HourlyRateCard({
    super.key,
    required this.hourlyRateData,
    required this.lastWeekAverageHourlyRate,
    required this.standardHourlyRate,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.canSwipeLeft = true,
  });

  @override
  Widget build(BuildContext context) {
    // 计算最大时薪，用于柱状图比例
    double maxHourlyRate = 0;
    for (var data in hourlyRateData) {
      if (data.hourlyRate > maxHourlyRate) {
        maxHourlyRate = data.hourlyRate;
      }
    }
    
    // 如果没有数据，设置最小值为标准时薪
    if (maxHourlyRate == 0) {
      maxHourlyRate = standardHourlyRate;
    }
    
    // 设置最小为10元，避免没有数据时的极端情况
    maxHourlyRate = maxHourlyRate < 10 ? 10 : maxHourlyRate;
    
    // 向上取整到最近的10的倍数，方便观看
    maxHourlyRate = (maxHourlyRate / 10).ceil() * 10.0;
    
    // 计算平均时薪
    double averageHourlyRate = 0;
    int validDataCount = 0;
    
    for (var data in hourlyRateData) {
      if (data.hourlyRate > 0) {
        averageHourlyRate += data.hourlyRate;
        validDataCount++;
      }
    }
    
    if (validDataCount > 0) {
      averageHourlyRate = averageHourlyRate / validDataCount;
    }
    
    // 生成比较小部件
    Widget? comparisonWidget;
    
    if (validDataCount > 0 && lastWeekAverageHourlyRate > 0) {
      // 计算变化百分比
      final changePercent = ((averageHourlyRate - lastWeekAverageHourlyRate) / lastWeekAverageHourlyRate) * 100;
      final absChangePercent = changePercent.abs().toStringAsFixed(1);
      
      // 创建比较小部件，使用图标
      if (changePercent > 0) {
        comparisonWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_upward,
              size: 12,
              color: Colors.grey[700]!,
            ),
            Text(
              " ${absChangePercent}%",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700]!,
              ),
            ),
          ],
        );
      } else if (changePercent < 0) {
        comparisonWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_downward,
              size: 12,
              color: Colors.grey[700]!,
            ),
            Text(
              " ${absChangePercent}%",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700]!,
              ),
            ),
          ],
        );
      } else {
        comparisonWidget = Text(
          "与上周持平",
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700]!,
          ),
        );
      }
    }
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            const Text(
              '平均时薪',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            // 平均时薪值与对比上周文案同一行
            if (validDataCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, // 让两个元素分布在两端
                  crossAxisAlignment: CrossAxisAlignment.end, // 使元素底部对齐
                  children: [
                    Text(
                      '¥${averageHourlyRate.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 24, // 更大的字体
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    if (comparisonWidget != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end, // 确保右对齐
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "对比上周 ",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700]!,
                                ),
                              ),
                              comparisonWidget,
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              
            const SizedBox(height: 16),
            
            // 柱状图
            SizedBox(
              height: 220,
              child: HourlyRateChart(
                data: hourlyRateData,
                maxHourlyRate: maxHourlyRate,
                onSwipeLeft: onSwipeLeft,
                onSwipeRight: onSwipeRight,
                canSwipeLeft: canSwipeLeft,
              ),
            ),
            
            // 分割线
            Divider(
              height: 32, // 上下各有16像素的间距
              thickness: 1,
              color: Colors.grey[300],
            ),
            
            // 额定时薪显示
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '额定时薪',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded( // 添加Expanded使额定时薪值可以右对齐
                  child: Text(
                    '¥${standardHourlyRate.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 14, // 使用正常字号
                      color: Colors.grey[700]!,
                    ),
                    textAlign: TextAlign.right, // 设置文本右对齐
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 