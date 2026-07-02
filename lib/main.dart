import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:google_fonts/google_fonts.dart'; // 👈 Google Fontsインポート

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);
  }
  runApp(const TsuruokaKosenTimetableApp());
}

class TsuruokaKosenTimetableApp extends StatelessWidget {
  const TsuruokaKosenTimetableApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NITTC Scheduler',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF64B5F6), brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        
        // ⭕ Google Fontsの「Zen Maru Gothic」をアプリ全体に適用！
        textTheme: GoogleFonts.zenMaruGothicTextTheme(ThemeData.light().textTheme),
        
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DayConfig {
  String weekType;
  String? substituteWeek;
  String? substituteDay;
  DayConfig({required this.weekType, this.substituteWeek, this.substituteDay});
  Map<String, dynamic> toJson() => {'weekType': weekType, 'substituteWeek': substituteWeek, 'substituteDay': substituteDay};
  factory DayConfig.fromJson(Map<String, dynamic> json) => DayConfig(weekType: json['weekType'], substituteWeek: json['substituteWeek'], substituteDay: json['substituteDay']);
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});
  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _screenIndex = 0;
  Map<String, DayConfig> _dayConfigs = {};
  List<DateTime> _weeks = [];
  DateTime? _selectedWeekMonday;
  int _todayTabIndex = 0;
  int _editDayIndex = 0;

  // --- 設定項目 ---
  int _periodCount = 4; // 1日のコマ数
  int _notificationBeforeMinutes = 10; // 何分前に通知するか
  Map<String, Map<String, TimeOfDay>> _periodTimes = {}; // 各コマの時間

  Map<String, List<Map<String, String>>> _timetableData = {};
  List<Map<String, dynamic>> _assignments = [];
  Map<String, dynamic> _dailyOverrides = {};

  @override
  void initState() {
    super.initState();
    _generateWeeks();
    _loadAllData().then((_) => _scheduleTodayNotifications());
  }

  void _generateWeeks() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    _weeks = List.generate(4, (index) => monday.add(Duration(days: index * 7)));
    _selectedWeekMonday = _weeks[0];
    if (now.weekday >= 1 && now.weekday <= 5) _todayTabIndex = now.weekday - 1;
  }

  String _timeToString(TimeOfDay time) => "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  
  TimeOfDay _stringToTime(String str) {
    final parts = str.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _periodCount = prefs.getInt('period_count') ?? 4;
      _notificationBeforeMinutes = prefs.getInt('notif_minutes') ?? 10;
      
      final timeJson = prefs.getString('period_times_v1');
      if (timeJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(timeJson);
        _periodTimes = decoded.map((key, value) => MapEntry(key, {
          "start": _stringToTime(value["start"]),
          "end": _stringToTime(value["end"]),
        }));
      } else {
        _periodTimes = {
          "1/2校時": {"start": const TimeOfDay(hour: 8, minute: 50), "end": const TimeOfDay(hour: 10, minute: 20)},
          "3/4校時": {"start": const TimeOfDay(hour: 10, minute: 30), "end": const TimeOfDay(hour: 12, minute: 0)},
          "5/6校時": {"start": const TimeOfDay(hour: 13, minute: 0), "end": const TimeOfDay(hour: 14, minute: 30)},
          "7/8校時": {"start": const TimeOfDay(hour: 14, minute: 40), "end": const TimeOfDay(hour: 16, minute: 10)},
        };
      }

      final configStr = prefs.getString('day_configs_v2');
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

      final timetableStr = prefs.getString('timetable_data_v5');
      if (timetableStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(timetableStr);
        _timetableData = decoded.map((day, periods) => MapEntry(day, (periods as List).map((p) => Map<String, String>.from(p as Map)).toList()));
      } else {
        for (var day in ["月", "火", "水", "木", "金"]) {
          _timetableData[day] = List.generate(8, (i) => {
            'period': "${i * 2 + 1}/${i * 2 + 2}校時",
            'subjectA': '', 'teacherA': '', 'roomA': '',
            'subjectB': '', 'teacherB': '', 'roomB': '',
            'isAlternate': 'false',
          });
        }
      }

      final assignmentStr = prefs.getString('assignments_v1');
      if (assignmentStr != null) _assignments = List<Map<String, dynamic>>.from(jsonDecode(assignmentStr));
      
      final overridesStr = prefs.getString('daily_overrides_v1');
      if (overridesStr != null) _dailyOverrides = jsonDecode(overridesStr);
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('period_count', _periodCount);
    await prefs.setInt('notif_minutes', _notificationBeforeMinutes);
    final timeJson = jsonEncode(_periodTimes.map((key, value) => MapEntry(key, {
      "start": _timeToString(value["start"]!),
      "end": _timeToString(value["end"]!),
    })));
    await prefs.setString('period_times_v1', timeJson);
    _scheduleTodayNotifications();
  }

  Future<void> _saveDayConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('day_configs_v2', jsonEncode(_dayConfigs.map((k, v) => MapEntry(k, v.toJson()))));
    _scheduleTodayNotifications();
  }

  Future<void> _saveTimetableData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timetable_data_v5', jsonEncode(_timetableData));
    _scheduleTodayNotifications();
  }

  Future<void> _saveDailyOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('daily_overrides_v1', jsonEncode(_dailyOverrides));
    _scheduleTodayNotifications();
  }

  Future<void> _saveAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assignments_v1', jsonEncode(_assignments));
  }

  String _formatDate(DateTime date) => "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  String _getDayName(int index) => ['月', '火', '水', '木', '金'][index];

  Future<void> _scheduleTodayNotifications() async {
    if (kIsWeb) return;
    await flutterLocalNotificationsPlugin.cancelAll();
    final now = DateTime.now();
    if (now.weekday > 5) return;
    final dateStr = _formatDate(now);
    final config = _dayConfigs[dateStr] ?? DayConfig(weekType: 'A');
    if (config.weekType == '休') return;

    final activeWeek = config.substituteWeek ?? config.weekType;
    final activeDay = config.substituteDay ?? _getDayName(now.weekday - 1);
    final lessons = _timetableData[activeDay] ?? [];

    for (int i = 0; i < _periodCount; i++) {
      if (i >= lessons.length) continue;
      final lesson = lessons[i];
      final period = lesson['period']!;
      final timeData = _periodTimes[period];
      if (timeData == null) continue;

      final overrideData = _dailyOverrides[dateStr]?[period];
      if (overrideData != null && overrideData['status'] == 'canceled') continue;

      String subject = (overrideData != null && overrideData['status'] == 'changed')
          ? overrideData['subject'] ?? ''
          : (lesson['isAlternate'] == 'true' && activeWeek == 'B' ? (lesson['subjectB'] ?? '') : (lesson['subjectA'] ?? ''));

      if (subject.isEmpty) continue;

      DateTime classStartTime = DateTime(now.year, now.month, now.day, timeData["start"]!.hour, timeData["start"]!.minute);
      DateTime notificationTime = classStartTime.subtract(Duration(minutes: _notificationBeforeMinutes));

      if (notificationTime.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id: i,
          title: 'まもなく授業開始',
          body: '次の授業は「$subject」です！',
          scheduledDate: tz.TZDateTime.from(notificationTime, tz.local),
          notificationDetails: const NotificationDetails(android: AndroidNotificationDetails('class_reminder', '授業通知', importance: Importance.high)),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }
  }

  // --- 右上の歯車アイコンタップで開く設定パネル ---
  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('アプリ詳細設定', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: 8),
                    Text('1日のコマ数: $_periodCount コマ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Slider(
                      value: _periodCount.toDouble(),
                      min: 1, max: 8, divisions: 7,
                      label: "$_periodCount コマ",
                      onChanged: (val) {
                        setState(() => _periodCount = val.toInt());
                        setModalState(() {});
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('通知タイミング: 授業開始の $_notificationBeforeMinutes 分前', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Slider(
                      value: _notificationBeforeMinutes.toDouble(),
                      min: 0, max: 30, divisions: 6,
                      label: "$_notificationBeforeMinutes 分前",
                      onChanged: (val) {
                        setState(() => _notificationBeforeMinutes = val.toInt());
                        setModalState(() {});
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text('各コマの時間帯調整', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                    const SizedBox(height: 8),
                    ...List.generate(_periodCount, (index) {
                      final periodKey = "${index * 2 + 1}/${index * 2 + 2}校時";
                      _periodTimes[periodKey] ??= {"start": const TimeOfDay(hour: 8, minute: 50), "end": const TimeOfDay(hour: 10, minute: 20)};
                      final times = _periodTimes[periodKey]!;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            SizedBox(width: 80, child: Text(periodKey, style: const TextStyle(fontWeight: FontWeight.bold))),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(context: context, initialTime: times['start']!);
                                  if (picked != null) {
                                    setState(() => _periodTimes[periodKey]!['start'] = picked);
                                    setModalState(() {});
                                    _saveSettings();
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                                  child: Text(_timeToString(times['start']!), textAlign: TextAlign.center),
                                ),
                              ),
                            ),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("~")),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(context: context, initialTime: times['end']!);
                                  if (picked != null) {
                                    setState(() => _periodTimes[periodKey]!['end'] = picked);
                                    setModalState(() {});
                                    _saveSettings();
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                                  child: Text(_timeToString(times['end']!), textAlign: TextAlign.center),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 長押しで休講にするメニュー ---
  void _showClassActionMenu(String dateStr, String period) {
    final bool hasOverride = _dailyOverrides[dateStr]?[period] != null;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasOverride)
                ListTile(
                  leading: const Icon(Icons.restore, color: Colors.green),
                  title: const Text('変更・休講を元に戻す'),
                  onTap: () {
                    setState(() {
                      _dailyOverrides[dateStr]?.remove(period);
                      if (_dailyOverrides[dateStr]?.isEmpty ?? false) _dailyOverrides.remove(dateStr);
                    });
                    _saveDailyOverrides();
                    Navigator.pop(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: const Text('この日のこのコマを休講にする'),
                onTap: () {
                  setState(() {
                    _dailyOverrides[dateStr] ??= {};
                    _dailyOverrides[dateStr][period] = {'status': 'canceled'};
                  });
                  _saveDailyOverrides();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- 新規課題の追加ダイアログ ---
  void _showAddAssignmentDialog() {
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final dateCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しい課題の登録'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '課題タイトル・内容')),
            TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: '対象科目')),
            TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: '提出締切日 (例: 7/12)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty) {
                setState(() {
                  _assignments.add({
                    'title': titleCtrl.text,
                    'subject': subjectCtrl.text,
                    'dueDate': dateCtrl.text,
                    'isCompleted': false,
                  });
                });
                _saveAssignments();
                Navigator.pop(context);
              }
            },
            child: const Text('登録'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NITTC Scheduler', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _showSettingsPanel), // ⚙️ 設定ボタン
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _screenIndex,
        children: [
          _buildTimetableTab(),
          _buildAssignmentTab(),
          const Center(child: Text("予定機能（今後拡張可能）")),
          _buildTimetableEditTab(),
          _buildConfigTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _screenIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _screenIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_on), label: '時間割'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined), label: '課題'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), label: '予定'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_calendar), label: '時間割編集'),
          BottomNavigationBarItem(icon: Icon(Icons.date_range), label: 'A/B表'),
        ],
      ),
    );
  }

  // ==================== 1. 時間割表示タブ ====================
  Widget _buildTimetableTab() {
    if (_selectedWeekMonday == null) return const Center(child: CircularProgressIndicator());
    return DefaultTabController(
      initialIndex: _todayTabIndex,
      length: 5,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: List.generate(5, (i) {
              final date = _selectedWeekMonday!.add(Duration(days: i));
              return Tab(text: "${date.month}/${date.day} (${_getDayName(i)})");
            }),
          ),
          Expanded(
            child: TabBarView(
              children: List.generate(5, (dayIndex) {
                final targetDate = _selectedWeekMonday!.add(Duration(days: dayIndex));
                final dateStr = _formatDate(targetDate);
                final config = _dayConfigs[dateStr] ?? DayConfig(weekType: 'A');
                if (config.weekType == '休') return const Center(child: Text('🛌 休日設定', style: TextStyle(fontSize: 24, color: Colors.grey)));

                final activeWeek = config.substituteWeek ?? config.weekType;
                final activeDay = config.substituteDay ?? _getDayName(dayIndex);
                final masterLessons = _timetableData[activeDay] ?? [];
                final nowTime = TimeOfDay.now();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _periodCount,
                  itemBuilder: (context, index) {
                    if (index >= masterLessons.length) return const SizedBox.shrink();
                    final masterItem = masterLessons[index];
                    final period = masterItem['period']!;
                    final isAlternate = masterItem['isAlternate'] == 'true';
                    
                    String sub = (isAlternate && activeWeek == 'B') ? (masterItem['subjectB'] ?? '') : (masterItem['subjectA'] ?? '');
                    String tea = (isAlternate && activeWeek == 'B') ? (masterItem['teacherB'] ?? '') : (masterItem['teacherA'] ?? '');
                    String rom = (isAlternate && activeWeek == 'B') ? (masterItem['roomB'] ?? '') : (masterItem['roomA'] ?? '');

                    final overrideData = _dailyOverrides[dateStr]?[period];
                    final bool isCanceled = overrideData != null && overrideData['status'] == 'canceled';
                    if (overrideData != null && overrideData['status'] == 'changed') {
                      sub = overrideData['subject'] ?? ''; tea = overrideData['teacher'] ?? ''; rom = overrideData['room'] ?? '';
                    }

                    final timeData = _periodTimes[period];
                    bool isCurrent = false;
                    if (targetDate.year == DateTime.now().year && targetDate.month == DateTime.now().month && targetDate.day == DateTime.now().day && timeData != null) {
                      final nowMin = nowTime.hour * 60 + nowTime.minute;
                      final startMin = timeData["start"]!.hour * 60 + timeData["start"]!.minute;
                      final endMin = timeData["end"]!.hour * 60 + timeData["end"]!.minute;
                      if (nowMin >= startMin && nowMin <= endMin) isCurrent = true;
                    }

                    return InkWell(
                      onLongPress: () => _showClassActionMenu(dateStr, period),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            Column(
                              children: [
                                Text(timeData != null ? _timeToString(timeData['start']!) : "--:--", style: TextStyle(fontSize: 11, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                                Container(width: 2, height: 50, color: isCurrent ? Colors.redAccent : Colors.grey[300], margin: const EdgeInsets.symmetric(vertical: 4)),
                                Text(timeData != null ? _timeToString(timeData['end']!) : "--:--", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white, borderRadius: BorderRadius.circular(16),
                                  border: isCurrent ? Border.all(color: Colors.redAccent, width: 2) : null,
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(isAlternate ? "$period ($activeWeek)" : period, style: TextStyle(color: isAlternate ? Colors.purple : Colors.blue, fontWeight: FontWeight.bold, fontSize: 11)),
                                        Text("$tea\n$rom", textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                    Text(sub.isEmpty ? '（未登録）' : sub, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, decoration: isCanceled ? TextDecoration.lineThrough : null, color: isCanceled ? Colors.red : Colors.black87)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 2. 課題管理タブ（完全復活＆強化版） ====================
  Widget _buildAssignmentTab() {
    return Scaffold(
      body: _assignments.isEmpty
          ? const Center(child: Text('現在、提出が必要な課題はありません！✨', style: TextStyle(fontSize: 16, color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _assignments.length,
              itemBuilder: (context, index) {
                final task = _assignments[index];
                final bool isDone = task['isCompleted'] ?? false;
                return Card(
                  elevation: isDone ? 0 : 2,
                  color: isDone ? Colors.grey[200] : Colors.white,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Checkbox(
                      value: isDone,
                      onChanged: (bool? value) {
                        setState(() => _assignments[index]['isCompleted'] = value);
                        _saveAssignments();
                      },
                    ),
                    title: Text(
                      task['title'] ?? '',
                      style: TextStyle(
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text("科目: ${task['subject'] ?? '指定なし'}  |  締切: ${task['dueDate'] ?? '未定'}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        setState(() => _assignments.removeAt(index));
                        _saveAssignments();
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddAssignmentDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  // ==================== 3. 時間割編集タブ ====================
  Widget _buildTimetableEditTab() {
    final dayName = _getDayName(_editDayIndex);
    final lessons = _timetableData[dayName] ?? [];
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (index) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _editDayIndex == index ? Colors.blue : Colors.grey[200],
                      foregroundColor: _editDayIndex == index ? Colors.white : Colors.black,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => setState(() => _editDayIndex = index),
                    child: Text(_getDayName(index)),
                  ),
                ),
              )),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _periodCount,
              itemBuilder: (context, index) {
                if (index >= lessons.length) return const SizedBox.shrink();
                return LessonEditCard(
                  key: ValueKey("$dayName-$index"),
                  lesson: lessons[index],
                  onSave: (updated) {
                    setState(() => _timetableData[dayName]![index] = updated);
                    _saveTimetableData();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 4. A/B表（週日程設定）タブ（完全復活） ====================
  Widget _buildConfigTab() {
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _weeks.length,
        itemBuilder: (context, weekIndex) {
          final monday = _weeks[weekIndex];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${monday.month}/${monday.day} の週", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (dayIndex) {
                      final targetDate = monday.add(Duration(days: dayIndex));
                      final dateStr = _formatDate(targetDate);
                      final config = _dayConfigs[dateStr] ?? DayConfig(weekType: 'A');

                      return Expanded(
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) {
                                String tempWeekType = config.weekType;
                                String? tempSubDay = config.substituteDay;
                                return AlertDialog(
                                  title: Text("${targetDate.month}/${targetDate.day} (${_getDayName(dayIndex)}) の設定"),
                                  content: StatefulBuilder(
                                    builder: (context, setDialogState) {
                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          DropdownButtonFormField<String>(
                                            value: tempWeekType,
                                            decoration: const InputDecoration(labelText: '週程 (A/B/休)'),
                                            items: ['A', 'B', '休'].map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                                            onChanged: (val) => setDialogState(() => tempWeekType = val!),
                                          ),
                                          const SizedBox(height: 16),
                                          DropdownButtonFormField<String?>(
                                            value: tempSubDay,
                                            decoration: const InputDecoration(labelText: '曜日の振替'),
                                            items: [
                                              const DropdownMenuItem(value: null, child: Text('通常通り')),
                                              ...['月', '火', '水', '木', '金'].map((d) => DropdownMenuItem(value: d, child: Text('$d曜日の授業にする'))),
                                            ],
                                            onChanged: (val) => setDialogState(() => tempSubDay = val),
                                          ),
                                        ],
                                      );
                                    }
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          config.weekType = tempWeekType;
                                          config.substituteDay = tempSubDay;
                                        });
                                        _saveDayConfigs();
                                        Navigator.pop(context);
                                      },
                                      child: const Text('保存'),
                                    ),
                                  ],
                                );
                              }
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            height: 65,
                            decoration: BoxDecoration(
                              color: config.weekType == 'A' ? Colors.blue[100] : (config.weekType == 'B' ? Colors.green[100] : Colors.grey[300]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("${targetDate.month}/${targetDate.day}", style: const TextStyle(fontSize: 10)),
                                Text(_getDayName(dayIndex), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                Text(config.weekType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                if (config.substituteDay != null)
                                  Text("${config.substituteDay}振替", style: const TextStyle(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              ],
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
}

// ==================== 5. 授業編集カード ====================
class LessonEditCard extends StatefulWidget {
  final Map<String, String> lesson;
  final Function(Map<String, String>) onSave;
  const LessonEditCard({super.key, required this.lesson, required this.onSave});
  @override
  State<LessonEditCard> createState() => _LessonEditCardState();
}

class _LessonEditCardState extends State<LessonEditCard> {
  late TextEditingController _subjectACtrl, _teacherACtrl, _roomACtrl, _subjectBCtrl, _teacherBCtrl, _roomBCtrl;
  late bool _isAlternate;
  @override
  void initState() {
    super.initState();
    _subjectACtrl = TextEditingController(text: widget.lesson['subjectA']);
    _teacherACtrl = TextEditingController(text: widget.lesson['teacherA']);
    _roomACtrl = TextEditingController(text: widget.lesson['roomA']);
    _subjectBCtrl = TextEditingController(text: widget.lesson['subjectB']);
    _teacherBCtrl = TextEditingController(text: widget.lesson['teacherB']);
    _roomBCtrl = TextEditingController(text: widget.lesson['roomB']);
    _isAlternate = widget.lesson['isAlternate'] == 'true';
  }
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(widget.lesson['period']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            TextField(controller: _subjectACtrl, decoration: const InputDecoration(labelText: '授業名 (A週)')),
            Row(children: [
              Expanded(child: TextField(controller: _teacherACtrl, decoration: const InputDecoration(labelText: '教員'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _roomACtrl, decoration: const InputDecoration(labelText: '教室'))),
            ]),
            if (_isAlternate) ...[
              const Divider(height: 24),
              TextField(controller: _subjectBCtrl, decoration: const InputDecoration(labelText: '授業名 (B週)')),
              Row(children: [
                Expanded(child: TextField(controller: _teacherBCtrl, decoration: const InputDecoration(labelText: '教員'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _roomBCtrl, decoration: const InputDecoration(labelText: '教室'))),
              ]),
            ],
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [Checkbox(value: _isAlternate, onChanged: (v) => setState(() => _isAlternate = v!)), const Text("隔週設定にする")]),
              ElevatedButton(onPressed: () {
                widget.onSave({
                  'period': widget.lesson['period']!,
                  'subjectA': _subjectACtrl.text, 'teacherA': _teacherACtrl.text, 'roomA': _roomACtrl.text,
                  'subjectB': _subjectBCtrl.text, 'teacherB': _teacherBCtrl.text, 'roomB': _roomBCtrl.text,
                  'isAlternate': _isAlternate.toString(),
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.lesson['period']}を保存しました！')));
              }, child: const Text("保存")),
            ]),
          ],
        ),
      ),
    );
  }
}