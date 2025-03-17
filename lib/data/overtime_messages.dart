import 'dart:math';

// 加班时长阈值（分钟）及对应的文案列表
final Map<int, List<String>> _overtimeMessages = {
  1: [
    "☠️建议将『跨出公司门时被喊回来』列入新型工伤鉴定标准",
  ],
  5: [
    "⏰加班能量警告：您刚刚燃烧了可兑换半颗茶叶蛋的青春",
    "🔒解锁宇宙级PUA：『你在为自己奋斗』≈『我的游艇缺个锚』",
  ],
  10: [
    "🌐解锁平行宇宙：此刻正常下班的你正在夏威夷吃菠萝披萨（系统崩溃版）",
    "🐱《消失的仪式感》- 痛失给猫主子开罐头的亲子互动时光",
    "🌌魔幻现实主义：朋友圈刷到前同事在冰岛看极光，而你在看代码极光",
  ],
  20: [
    "💼系统公告：您已自动续费『老板の财务自由梦想』终极众筹计划",
    "💎解锁成就：用加班时长兑换老板新表⌚秒针跳动0.3圈",
    "💆‍♂️温馨提示：您的心脏正在申请『不为老板梦想跳动』基本人权",
  ],
  30: [
    "💆‍♂️系统提示：您的植发成活率正以200%速度向地中海退化",
    "📺当加班时长=追完一集《甄嬛传》，你就是钮祜禄·改不完方案·氏",
    "💆‍♂️史诗成就：让蟑螂产生『这货比我能熬』的种族焦虑",
  ],
  60: [
    "🎮一小时=痛失在steam夏促游戏里体验当甲方的珍贵人生",
    "⚠️系统警告：您已错过黄金植发预约时段并解锁地中海皮肤体验",
    "💆‍♂️恭喜！您为老板小三的铂金包贡献了0.00001%空气使用权",
    "⛵️《时间通货膨胀》- 你燃烧1小时≈老板游艇多1厘米油漆",
  ],
  90: [
    "⚠️系统提示：您的肝已自动续费『福报人生尊享套餐』",
  ],
  120: [
    "💆‍♂️两小时定律：足够让老板从『你很努力』进化到『我觉得你可以再突破』",
  ],
  180: [
    "📖解锁《山海经》新物种：拥有黑眼圈の当代刑天（以肝代首版）",
  ],
  240: [
    "🎬当加班时长=看完《指环王》三部曲，你就是中土世界のPPT护戒使者",
  ],
  300: [
    "💆‍♂️五小时渡劫指南：从打工人到修仙者的基因突变已完成87.53%",
  ],
};

// 跟踪上次更新时间和信息
DateTime? _lastMessageUpdateTime;
String? _currentOvertimeMessage;
int? _lastOvertimeThreshold;

/// 根据加班时长获取随机文案
String getRandomOvertimeMessage(Duration overtimeDuration) {
  // 将加班时长转换为分钟
  final overtimeMinutes = overtimeDuration.inMinutes;
  
  // 确定当前加班时长对应的阈值
  int currentThreshold = 1; // 默认最低阈值
  
  // 查找适用的最大阈值
  for (final threshold in _overtimeMessages.keys) {
    if (overtimeMinutes >= threshold) {
      currentThreshold = threshold;
    } else {
      break;
    }
  }
  
  // 检查是否需要更新消息
  final now = DateTime.now();
  
  // 如果尚未设置消息，或者已经过了5分钟，或者阈值发生了变化，则更新消息
  if (_currentOvertimeMessage == null || 
      _lastMessageUpdateTime == null || 
      now.difference(_lastMessageUpdateTime!).inMinutes >= 5 ||
      _lastOvertimeThreshold != currentThreshold) {
    
    // 获取当前阈值对应的文案列表
    final messages = _overtimeMessages[currentThreshold]!;
    
    // 随机选择一条文案
    final random = Random();
    _currentOvertimeMessage = messages[random.nextInt(messages.length)];
    
    // 更新最后更新时间和阈值
    _lastMessageUpdateTime = now;
    _lastOvertimeThreshold = currentThreshold;
  }
  
  return _currentOvertimeMessage!;
} 