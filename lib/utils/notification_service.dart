import 'package:flutter/material.dart';

/// 通知服务类，用于处理应用内通知
class NotificationService {
  // 单例模式
  static final NotificationService _instance = NotificationService._internal();
  
  factory NotificationService() {
    return _instance;
  }
  
  NotificationService._internal();
  
  // 显示通知的方法 (可以根据需要扩展)
  void showNotification(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
} 