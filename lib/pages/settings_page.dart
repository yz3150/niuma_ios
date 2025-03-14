import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../utils/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late String _salaryType;
  final TextEditingController _salaryController = TextEditingController();
  
  bool _isFormChanged = false;
  final SettingsService _settingsService = SettingsService();
  
  late final TimeOfDay _initialStartTime;
  late final TimeOfDay _initialEndTime;
  late final String _initialSalaryType;
  late final String _initialSalary;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _startTime = _settingsService.getStartTime();
    _endTime = _settingsService.getEndTime();
    _salaryType = _settingsService.getSalaryType();
    final salary = _settingsService.getSalary();
    _salaryController.text = salary.toString();

    _initialStartTime = _startTime;
    _initialEndTime = _endTime;
    _initialSalaryType = _salaryType;
    _initialSalary = _salaryController.text;

    _salaryController.addListener(_checkFormChanged);
  }

  @override
  void dispose() {
    _salaryController.removeListener(_checkFormChanged);
    _salaryController.dispose();
    super.dispose();
  }

  void _checkFormChanged() {
    final bool isChanged = 
      _startTime != _initialStartTime ||
      _endTime != _initialEndTime ||
      _salaryType != _initialSalaryType ||
      _salaryController.text != _initialSalary;

    if (isChanged != _isFormChanged) {
      setState(() {
        _isFormChanged = isChanged;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          actions: [
            TextButton(
              onPressed: _isFormChanged ? _handleSubmit : null,
              child: Text(
                '提交',
                style: TextStyle(
                  color: _isFormChanged ? AppTheme.primaryColor : Colors.grey,
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildTimeSection('上班时间', _startTime, (time) {
              setState(() {
                _startTime = time;
                _checkFormChanged();
              });
            }),
            const SizedBox(height: 16),
            _buildTimeSection('下班时间', _endTime, (time) {
              setState(() {
                _endTime = time;
                _checkFormChanged();
              });
            }),
            const SizedBox(height: 16),
            _buildSalaryTypeSection(),
            const SizedBox(height: 16),
            _buildSalarySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSection(String title, TimeOfDay time, Function(TimeOfDay) onChanged) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
        onTap: () async {
          final TimeOfDay? picked = await showTimePicker(
            context: context,
            initialTime: time,
          );
          if (picked != null) {
            onChanged(picked);
          }
        },
      ),
    );
  }

  Widget _buildSalaryTypeSection() {
    return Card(
      child: ListTile(
        title: const Text('薪资类型'),
        trailing: DropdownButton<String>(
          value: _salaryType,
          items: const [
            DropdownMenuItem(value: '月薪', child: Text('月薪')),
            DropdownMenuItem(value: '日薪', child: Text('日薪')),
            DropdownMenuItem(value: '时薪', child: Text('时薪')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _salaryType = value;
                _checkFormChanged();
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildSalarySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _salaryController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: const InputDecoration(
            labelText: '薪资',
            border: OutlineInputBorder(),
            errorMaxLines: 2,
          ),
          onChanged: (value) {
            if (value == '.') {
              _salaryController.text = '0.';
              _salaryController.selection = TextSelection.fromPosition(
                TextPosition(offset: _salaryController.text.length),
              );
            }
          },
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (_isFormChanged) {
      return await _showConfirmDialog() ?? false;
    }
    return true;
  }

  void _handleBack() async {
    if (_isFormChanged) {
      final shouldPop = await _showConfirmDialog();
      if (shouldPop ?? false) {
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } else {
      Navigator.pop(context);
    }
  }

  Future<bool> _showConfirmDialog() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('提示'),
          content: const Text('设置数据有更新，是否提交？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('否'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                '是',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handleSubmit() async {
    if (_salaryController.text.isEmpty) {
      _showToast('请输入薪资');
      return;
    }

    try {
      await _settingsService.setStartTime(_startTime);
      await _settingsService.setEndTime(_endTime);
      await _settingsService.setSalaryType(_salaryType);
      await _settingsService.setSalary(double.parse(_salaryController.text));

      _showToast('设置成功');
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _showToast('保存设置失败');
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
} 