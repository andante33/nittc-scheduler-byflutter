import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  runApp(const TsuruokaKosenTimetableApp());
}

class TsuruokaKosenTimetableApp extends StatelessWidget {
  const TsuruokaKosenTimetableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '鶴岡高専 時間割 & 課題',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 日程設定を保持するクラス
class DayConfig {
  String weekType; 
  String? substituteWeek; 
  String? substituteDay;  

  DayConfig({required this.weekType, this.substituteWeek, this.substituteDay});

  Map<String, dynamic> toJson() => {
        'weekType': weekType,
        'substituteWeek': substituteWeek,
        'substituteDay': substituteDay,
      };

  factory DayConfig.fromJson(Map<String, dynamic> json) => DayConfig(
        weekType: json['weekType'],
        substituteWeek: json['substituteWeek'],
        substituteDay: json['substituteDay'],
      );
}

// --- メイン画面（4タブ切り替え） ---
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _screenIndex = 0; // 0:時間割, 1:授業設定, 2:週日程設定, 3:課題管理
  Map<String, DayConfig> _dayConfigs = {};
  List<DateTime> _weeks = [];
  DateTime? _selectedWeekMonday;

  // 動的な時間割データ
  Map<String, Map<String, List<Map<String, String>>>> _timetableData = {};

  // 課題データリスト
  List<Map<String, dynamic>> _assignments = [];

  // 授業設定タブ用の一時選択状態
  String _configSelectedWeek = 'A';
  String _configSelectedDay = '月';

  // デフォルトの時間割データ（データが空の時の初期値）
  final Map<String, Map<String, List<Map<String, String>>>> _defaultTimetable = {
    'A': {
      '月': [{'period': '1-2限', 'subject': '[A] 微分積分I', 'room': '一般棟 201', 'teacher': '佐藤 教授'}, {'period': '3-4限', 'subject': '情報プログラミング', 'room': '電子計算機室', 'teacher': '鈴木 准教授'}],
      '火': [{'period': '1-2限', 'subject': '[A] 物理基礎', 'room': '物理実験室', 'teacher': '高橋 講師'}],
      '水': [{'period': '1-2限', 'subject': '専門基礎実験', 'room': '各実験室', 'teacher': '田中 教授'}],
      '木': [{'period': '1-2限', 'subject': '[A] 歴史', 'room': '一般棟 201', 'teacher': '渡辺 講師'}],
      '金': [{'period': '1-2限', 'subject': '選択英語', 'room': '選択教室', 'teacher': '伊藤 講師'}],
    },
    'B': {
      '月': [{'period': '1-2限', 'subject': '[B] 線形代数', 'room': '一般棟 201', 'teacher': '佐藤 教授'}, {'period': '3-4限', 'subject': '応用化学', 'room': '化学実験室', 'teacher': '山本 教授'}],
      '火': [{'period': '1-2限', 'subject': '[B] 国語表現', 'room': '一般棟 201', 'teacher': '中村 講師'}],
      '水': [{'period': '1-2限', 'subject': '専門基礎実験', 'room': '各実験室', 'teacher': '田中 教授'}],
      '木': [{'period': '1-2限', 'subject': '[B] 応用数学', 'room': '一般棟 201', 'teacher': '小林 准教授'}],
      '金': [{'period': '1-2限', 'subject': '自由放課', 'room': '-', 'teacher': '-'}],
    }
  };

  @override
  void initState() {
    super.initState();
    _generateWeeks();
    _loadAllData();
  }

  void _generateWeeks() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    _weeks = List.generate(4, (index) => monday.add(Duration(days: index * 7)));
    _selectedWeekMonday = _weeks[0]; 
  }

  // すべてのデータを一括読み込み
  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. カレンダー日程設定の読み込み
    final configStr = prefs.getString('day_configs_v2');
    // 2. 時間割データの読み込み
    final timetableStr = prefs.getString('timetable_data_v3');
    // 3. 課題データの読み込み
    final assignmentStr = prefs.getString('assignments_v1');

    setState(() {
      // 日程設定デコード
      if (configStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(configStr);
        _dayConfigs = decoded.map((key, value) => MapEntry(key, DayConfig.fromJson(value)));
      } else {
        for (var w = 0; w < _weeks.length; w++) {
          final defaultType = (w % 2 == 0) ? 'A' : 'B';
          for (var d = 0; d < 5; d++) {
            final dateStr = _formatDate(_weeks[w].add(Duration(days: d)));
            _dayConfigs[dateStr] = DayConfig(weekType: defaultType);
          }
        }
      }

      // 時間割デコード
      if (timetableStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(timetableStr);
        _timetableData = decoded.map((week, days) {
          return MapEntry(week, (days as Map<String, dynamic>).map((day, periods) {
            return MapEntry(day, (periods as List).map((p) => Map<String, String>.from(p as Map)).toList());
          }));
        });
      } else {
        _timetableData = _defaultTimetable;
      }

      // 課題データデコード
      if (assignmentStr != null) {
        _assignments = List<Map<String, dynamic>>.from(jsonDecode(assignmentStr));
      }
    });
  }

  // データの保存処理
  Future<void> _saveDayConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('day_configs_v2', jsonEncode(_dayConfigs.map((key, value) => MapEntry(key, value.toJson()))));
  }

  Future<void> _saveTimetableData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timetable_data_v3', jsonEncode(_timetableData));
  }

  Future<void> _saveAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assignments_v1', jsonEncode(_assignments));
  }

  String _formatDate(DateTime date) =>
      "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

  String _getDayName(int index) => ['月', '火', '水', '木', '金'][index];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _screenIndex,
        children: [
          _buildTimetableTab(),
          _buildLessonConfigTab(), // 授業マスター設定
          _buildConfigTab(),
          _buildAssignmentTab(),   // 課題管理
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _screenIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _screenIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: '時間割'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '授業設定'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_calendar), label: '週日程設定'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: '課題管理'),
        ],
      ),
    );
  }

  // ==================== 0. 時間割表示タブ ====================
  Widget _buildTimetableTab() {
    if (_selectedWeekMonday == null || _dayConfigs.isEmpty || _timetableData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: DropdownButtonHideUnderline(
            child: DropdownButton<DateTime>(
              value: _selectedWeekMonday,
              dropdownColor: Colors.teal[700],
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              items: _weeks.map((week) {
                final isCurrent = week == _weeks[0] ? ' (今週)' : '';
                return DropdownMenuItem(
                  value: week,
                  child: Text("${week.month}/${week.day}の週$isCurrent"),
                );
              }).toList(),
              onChanged: (DateTime? newValue) {
                setState(() => _selectedWeekMonday = newValue);
              },
            ),
          ),
          backgroundColor: Colors.teal,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amber,
            tabs: List.generate(5, (i) => Tab(text: _getDayName(i))),
          ),
        ),
        body: TabBarView(
          children: List.generate(5, (dayIndex) {
            final targetDate = _selectedWeekMonday!.add(Duration(days: dayIndex));
            final dateStr = _formatDate(targetDate);
            final config = _dayConfigs[dateStr] ?? DayConfig(weekType: 'A');

            if (config.weekType == '休') {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🛌', style: TextStyle(fontSize: 50)),
                    SizedBox(height: 10),
                    Text('この日は休日設定です', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ],
                ),
              );
            }

            final activeWeek = config.substituteWeek ?? config.weekType;
            final activeDay = config.substituteDay ?? _getDayName(dayIndex);
            final isSubstituted = config.substituteDay != null;

            final subjects = _timetableData[activeWeek]?[activeDay] ?? [];

            return Column(
              children: [
                if (isSubstituted)
                  Container(
                    width: double.infinity,
                    color: Colors.amber[100],
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "特別日程: 【$activeWeek週 $activeDay曜日】を適用中",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: subjects.isEmpty
                      ? const Center(child: Text('この曜日の授業は登録されていません'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: subjects.length,
                          itemBuilder: (context, index) {
                            final item = subjects[index];
                            return Card(
                              elevation: 2,
                              child: ListTile(
                                leading: Text(item['period']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 15)),
                                title: Text(item['subject']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text("📍 ${item['room']!}  |  👤 ${item['teacher'] ?? '未設定'}"),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ==================== 1. 授業情報設定タブ ====================
  Widget _buildLessonConfigTab() {
    if (_timetableData.isEmpty) return const Center(child: CircularProgressIndicator());

    final currentLessons = _timetableData[_configSelectedWeek]?[_configSelectedDay] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('授業データ編集', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
      ),
      body: Column(
        children: [
          // 週と曜日のセレクター
          Container(
            color: Colors.teal[50],
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DropdownButton<String>(
                  value: _configSelectedWeek,
                  items: ['A', 'B'].map((w) => DropdownMenuItem(value: w, child: Text('$w 週'))).toList(),
                  onChanged: (val) => setState(() => _configSelectedWeek = val!),
                ),
                DropdownButton<String>(
                  value: _configSelectedDay,
                  items: ['月', '火', '水', '木', '金'].map((d) => DropdownMenuItem(value: d, child: Text('$d 曜日'))).toList(),
                  onChanged: (val) => setState(() => _configSelectedDay = val!),
                ),
              ],
            ),
          ),
          // コマ一覧
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: currentLessons.length,
              itemBuilder: (context, index) {
                final lesson = currentLessons[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.teal, child: Text(lesson['period']!.replaceAll('限', ''), style: const TextStyle(color: Colors.white, fontSize: 12))),
                    title: Text(lesson['subject']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("場所: ${lesson['room']} / 教員: ${lesson['teacher'] ?? '-'}"),
                    trailing: const Icon(Icons.edit, color: Colors.teal),
                    onTap: () => _showEditLessonDialog(index, lesson),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddLessonDialog,
        icon: const Icon(Icons.add),
        label: const Text('新しくコマを追加'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    );
  }

  // 授業の編集ダイアログ
  void _showEditLessonDialog(int index, Map<String, String> lesson) {
    final periodCtrl = TextEditingController(text: lesson['period']);
    final subjectCtrl = TextEditingController(text: lesson['subject']);
    final roomCtrl = TextEditingController(text: lesson['room']);
    final teacherCtrl = TextEditingController(text: lesson['teacher'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_configSelectedWeek}週 (${_configSelectedDay}) 授業変更'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: periodCtrl, decoration: const InputDecoration(labelText: '時間 (例: 1-2限)')),
              TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: '授業名')),
              TextField(controller: roomCtrl, decoration: const InputDecoration(labelText: '教室・場所')),
              TextField(controller: teacherCtrl, decoration: const InputDecoration(labelText: '担当教員')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _timetableData[_configSelectedWeek]?[_configSelectedDay]?.removeAt(index);
              });
              _saveTimetableData();
              Navigator.pop(context);
            },
            child: const Text('このコマを削除', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              setState(() {
                // 【修正箇所】こちら側も正しくカッコを補完して [_configSelectedDay] に直しました！
                _timetableData[_configSelectedWeek]?[_configSelectedDay]?[index] = {
                  'period': periodCtrl.text,
                  'subject': subjectCtrl.text,
                  'room': roomCtrl.text,
                  'teacher': teacherCtrl.text,
                };
              });
              _saveTimetableData();
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 授業の新規追加ダイアログ
  void _showAddLessonDialog() {
    final periodCtrl = TextEditingController(text: '1-2限');
    final subjectCtrl = TextEditingController();
    final roomCtrl = TextEditingController();
    final teacherCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_configSelectedWeek}週 (${_configSelectedDay}) に新規追加'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: periodCtrl, decoration: const InputDecoration(labelText: '時間 (例: 5-6限)')),
              TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: '授業名')),
              TextField(controller: roomCtrl, decoration: const InputDecoration(labelText: '教室・場所')),
              TextField(controller: teacherCtrl, decoration: const InputDecoration(labelText: '担当教員')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              if (subjectCtrl.text.isEmpty) return;
              setState(() {
                _timetableData[_configSelectedWeek]?[_configSelectedDay]?.add({
                  'period': periodCtrl.text,
                  'subject': subjectCtrl.text,
                  'room': roomCtrl.text,
                  'teacher': teacherCtrl.text,
                });
              });
              _saveTimetableData();
              Navigator.pop(context);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  // ==================== 2. 週・日程設定タブ ====================
  Widget _buildConfigTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('週・日程スケジュール設定', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _weeks.length,
        itemBuilder: (context, weekIndex) {
          final monday = _weeks[weekIndex];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 10),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              key: ValueKey(monday),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${monday.month}/${monday.day} の週 (${weekIndex == 0 ? '今週' : '来週以降'})",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (dayIndex) {
                      final targetDate = monday.add(Duration(days: dayIndex));
                      final dateStr = _formatDate(targetDate);
                      final config = _dayConfigs[dateStr] ?? DayConfig(weekType: 'A');

                      Color btnColor = Colors.blue;
                      if (config.weekType == 'B') btnColor = Colors.green;
                      if (config.weekType == '休') btnColor = Colors.grey;

                      final hasSub = config.substituteDay != null;

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (config.weekType == 'A') {
                                  config.weekType = 'B';
                                } else if (config.weekType == 'B') {
                                  config.weekType = '休';
                                } else {
                                  config.weekType = 'A';
                                }
                                config.substituteWeek = null;
                                config.substituteDay = null;
                              });
                              _saveDayConfigs();
                            },
                            onLongPress: () => _showSubDialog(dateStr, _getDayName(dayIndex), config),
                            child: Container(
                              height: 65,
                              decoration: BoxDecoration(
                                color: btnColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: btnColor, width: hasSub ? 2.5 : 1.0),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_getDayName(dayIndex), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text(
                                    config.weekType,
                                    style: TextStyle(fontWeight: FontWeight.bold, color: btnColor, fontSize: 14),
                                  ),
                                  if (hasSub)
                                    Text(
                                      "→${config.substituteWeek}${config.substituteDay}",
                                      style: const TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSubDialog(String dateStr, String originDay, DayConfig config) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$dateStr ($originDay) の時間割変更'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('この日に適用する時間割を選んでください：', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 15),
              const Text('【A週の時間割をやる】', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              Wrap(
                spacing: 5,
                children: ['月', '火', '水', '木', '金'].map((d) {
                  return ChoiceChip(
                    label: Text('A$d'),
                    selected: config.substituteWeek == 'A' && config.substituteDay == d,
                    onSelected: (_) {
                      setState(() {
                        config.substituteWeek = 'A';
                        config.substituteDay = d;
                      });
                      _saveDayConfigs();
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              const Text('【B週の時間割をやる】', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              Wrap(
                spacing: 5,
                children: ['月', '火', '水', '木', '金'].map((d) {
                  return ChoiceChip(
                    label: Text('B$d'),
                    selected: config.substituteWeek == 'B' && config.substituteDay == d,
                    onSelected: (_) {
                      setState(() {
                        config.substituteWeek = 'B';
                        config.substituteDay = d;
                      });
                      _saveDayConfigs();
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  config.substituteWeek = null;
                  config.substituteDay = null;
                });
                _saveDayConfigs();
                Navigator.pop(context);
              },
              child: const Text('通常日程（リセット）', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  // ==================== 3. 課題管理タブ ====================
  Widget _buildAssignmentTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('課題管理 (ToDo)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
      ),
      body: _assignments.isEmpty
          ? const Center(child: Text('現在、未提出の課題はありません！✨'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _assignments.length,
              itemBuilder: (context, index) {
                final task = _assignments[index];
                final bool isDone = task['isCompleted'] ?? false;

                return Card(
                  color: isDone ? Colors.grey[200] : Colors.white,
                  child: ListTile(
                    leading: Checkbox(
                      value: isDone,
                      onChanged: (bool? value) {
                        setState(() {
                          _assignments[index]['isCompleted'] = value;
                        });
                        _saveAssignments();
                      },
                    ),
                    title: Text(
                      task['title'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey : Colors.black,
                      ),
                    ),
                    subtitle: Text("科目: ${task['subject']}  |  締切: ${task['dueDate']}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          _assignments.removeAt(index);
                        });
                        _saveAssignments();
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddAssignmentDialog,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_task),
      ),
    );
  }

  // 課題追加のダイアログ
  void _showAddAssignmentDialog() {
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    String selectedDateStr = _formatDate(DateTime.now());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新しい課題を追加'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '課題内容 (レポート、小テストなど)')),
              TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: '対象科目')),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("締切日: $selectedDateStr", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDateStr = _formatDate(picked);
                        });
                      }
                    },
                    child: const Text('日付選択'),
                  ),
                ],
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
            TextButton(
              onPressed: () {
                if (titleCtrl.text.isEmpty) return;
                setState(() {
                  _assignments.add({
                    'title': titleCtrl.text,
                    'subject': subjectCtrl.text.isEmpty ? 'その他' : subjectCtrl.text,
                    'dueDate': selectedDateStr,
                    'isCompleted': false,
                  });
                });
                _saveAssignments();
                Navigator.pop(context);
              },
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
  }
}