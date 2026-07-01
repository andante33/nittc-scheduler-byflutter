import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // 新・データ構造 { "月": [ { period, subjectA, teacherA, roomA, subjectB, teacherB, roomB, isAlternate }, ... ] }
  Map<String, List<Map<String, String>>> _timetableData = {};
  List<Map<String, dynamic>> _assignments = [];
  Map<String, dynamic> _dailyOverrides = {};

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

    if (now.weekday >= 1 && now.weekday <= 5) {
      _todayTabIndex = now.weekday - 1;
    }
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString('day_configs_v2');
    final timetableStr = prefs.getString('timetable_data_v5'); // 授業名も分離した最新キー
    final assignmentStr = prefs.getString('assignments_v1');
    final overridesStr = prefs.getString('daily_overrides_v1');

    setState(() {
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

      if (timetableStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(timetableStr);
        _timetableData = decoded.map((day, periods) {
          return MapEntry(day, (periods as List).map((p) => Map<String, String>.from(p as Map)).toList());
        });
      } else {
        final periods = ["1/2校時", "3/4校時", "5/6校時", "7/8校時"];
        for (var day in ["月", "火", "水", "木", "金"]) {
          _timetableData[day] = periods.map((p) => {
            'period': p,
            'subjectA': '',
            'teacherA': '',
            'roomA': '',
            'subjectB': '',
            'teacherB': '',
            'roomB': '',
            'isAlternate': 'false',
          }).toList();
        }
      }

      if (assignmentStr != null) {
        _assignments = List<Map<String, dynamic>>.from(jsonDecode(assignmentStr));
      }

      if (overridesStr != null) {
        _dailyOverrides = jsonDecode(overridesStr);
      }
    });
  }

  Future<void> _saveDayConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('day_configs_v2', jsonEncode(_dayConfigs.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> _saveTimetableData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timetable_data_v5', jsonEncode(_timetableData));
  }

  Future<void> _saveDailyOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('daily_overrides_v1', jsonEncode(_dailyOverrides));
  }

  Future<void> _saveAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assignments_v1', jsonEncode(_assignments));
  }

  String _formatDate(DateTime date) => "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  String _getDayName(int index) => ['月', '火', '水', '木', '金'][index];

  // 検索用：A週・B週両方の科目を抽出
  List<Map<String, String>> _getAllUniqueSubjects() {
    List<Map<String, String>> all = [];
    Set<String> seen = {};
    _timetableData.forEach((day, lessons) {
      for (var l in lessons) {
        final subA = l['subjectA'] ?? '';
        if (subA.isNotEmpty && !seen.contains(subA)) {
          seen.add(subA);
          all.add({'subject': subA, 'room': l['roomA'] ?? '', 'teacher': l['teacherA'] ?? ''});
        }
        final subB = l['subjectB'] ?? '';
        if (subB.isNotEmpty && !seen.contains(subB)) {
          seen.add(subB);
          all.add({'subject': subB, 'room': l['roomB'] ?? '', 'teacher': l['teacherB'] ?? ''});
        }
      }
    });
    return all;
  }

  // 次回の授業日検索（A/B週の授業名に完全対応）
  DateTime? _findNextClassDate(String subjectQuery) {
    if (subjectQuery.isEmpty) return null;
    DateTime currentDate = DateTime.now().add(const Duration(days: 1));
    
    for (int i = 0; i < 30; i++) {
      String dateStr = _formatDate(currentDate);
      DayConfig config = _dayConfigs[dateStr] ?? DayConfig(weekType: 'A');
      
      if (config.weekType == '休' || currentDate.weekday > 5) {
        currentDate = currentDate.add(const Duration(days: 1));
        continue;
      }
      
      String activeWeek = config.substituteWeek ?? config.weekType;
      String activeDay = config.substituteDay ?? _getDayName(currentDate.weekday - 1);
      List<Map<String, String>> lessons = _timetableData[activeDay] ?? [];

      for (var lesson in lessons) {
        final override = _dailyOverrides[dateStr]?[lesson['period']];
        if (override != null && override['status'] == 'canceled') continue;

        String checkSubject = '';
        if (override != null && override['status'] == 'changed') {
          checkSubject = override['subject'] ?? '';
        } else {
          final isAlt = lesson['isAlternate'] == 'true';
          checkSubject = (isAlt && activeWeek == 'B') ? (lesson['subjectB'] ?? '') : (lesson['subjectA'] ?? '');
        }
            
        if (checkSubject.contains(subjectQuery)) {
          return currentDate;
        }
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _screenIndex,
        children: [
          _buildTimetableTab(),
          _buildAssignmentTab(),
          const Center(child: Text("予定（今後実装）")), 
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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('NITTC Scheduler', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            isScrollable: true,
            tabs: List.generate(5, (i) {
              final date = _selectedWeekMonday!.add(Duration(days: i));
              return Tab(text: "${date.month}/${date.day} (${_getDayName(i)})");
            }),
          ),
        ),
        body: TabBarView(
          children: List.generate(5, (dayIndex) {
            final targetDate = _selectedWeekMonday!.add(Duration(days: dayIndex));
            final dateStr = _formatDate(targetDate);
            final config = _dayConfigs[dateStr] ?? DayConfig(weekType: 'A');
            
            if (config.weekType == '休') {
              return const Center(child: Text('🛌 休日設定', style: TextStyle(fontSize: 24, color: Colors.grey)));
            }

            final activeWeek = config.substituteWeek ?? config.weekType;
            final activeDay = config.substituteDay ?? _getDayName(dayIndex);
            final masterLessons = _timetableData[activeDay] ?? [];

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: masterLessons.length,
              itemBuilder: (context, index) {
                final masterItem = masterLessons[index];
                final period = masterItem['period']!;
                final isAlternate = masterItem['isAlternate'] == 'true';
                
                // 授業名・教員・教室のすべてをA/B週で切り替え
                String displaySubject = '';
                String displayTeacher = '';
                String displayRoom = '';

                if (isAlternate && activeWeek == 'B') {
                  displaySubject = masterItem['subjectB'] ?? '';
                  displayTeacher = masterItem['teacherB'] ?? '';
                  displayRoom = masterItem['roomB'] ?? '';
                } else {
                  displaySubject = masterItem['subjectA'] ?? '';
                  displayTeacher = masterItem['teacherA'] ?? '';
                  displayRoom = masterItem['roomA'] ?? '';
                }

                // 当日の個別上書き判定
                final overrideData = _dailyOverrides[dateStr]?[period];
                final bool isCanceled = overrideData != null && overrideData['status'] == 'canceled';
                final bool isChanged = overrideData != null && overrideData['status'] == 'changed';

                if (isChanged && overrideData != null) {
                  displaySubject = overrideData['subject'] ?? '';
                  displayTeacher = overrideData['teacher'] ?? '';
                  displayRoom = overrideData['room'] ?? '';
                }

                return InkWell(
                  onLongPress: () => _showClassActionMenu(dateStr, period, displaySubject),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Text("開始", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            Container(width: 2, height: 60, color: Colors.grey[300], margin: const EdgeInsets.symmetric(vertical: 4)),
                            Text("終了", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isAlternate ? Colors.purple[50] : Colors.blue[50],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(isAlternate ? "$period ($activeWeek週)" : period, style: TextStyle(color: isAlternate ? Colors.purple : Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    Text("$displayTeacher\n$displayRoom", textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  displaySubject.isEmpty ? '（未登録）' : displaySubject,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    decoration: isCanceled ? TextDecoration.lineThrough : null,
                                    color: isCanceled ? Colors.red : (displaySubject.isEmpty ? Colors.grey : Colors.black87),
                                  ),
                                ),
                                if (isChanged)
                                  const Text("※授業変更適用中", style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
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
    );
  }

  void _showClassActionMenu(String dateStr, String period, String currentSubject) {
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
                  title: const Text('変更・休講を元に戻す (通常授業へ)'),
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
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                title: const Text('別の授業に変更する（検索）'),
                onTap: () {
                  Navigator.pop(context);
                  _showSearchSubjectDialog(dateStr, period);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSearchSubjectDialog(String dateStr, String period) {
    String searchQuery = '';
    final allSubjects = _getAllUniqueSubjects();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = allSubjects.where((s) => (s['subject'] ?? '').toLowerCase().contains(searchQuery.toLowerCase())).toList();
          return AlertDialog(
            title: Text('$dateStr $period の授業変更'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: '科目名で検索', prefixIcon: Icon(Icons.search)),
                    onChanged: (val) => setDialogState(() => searchQuery = val),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final sub = filtered[index];
                        return ListTile(
                          title: Text(sub['subject'] ?? ''),
                          subtitle: Text("${sub['room']} / ${sub['teacher']}"),
                          onTap: () {
                            setState(() {
                              _dailyOverrides[dateStr] ??= {};
                              _dailyOverrides[dateStr][period] = {
                                'status': 'changed',
                                'subject': sub['subject'],
                                'room': sub['room'],
                                'teacher': sub['teacher'],
                              };
                            });
                            _saveDailyOverrides();
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
            ],
          );
        }
      ),
    );
  }

  // ==================== 2. 時間割編集タブ ====================
  Widget _buildTimetableEditTab() {
    final dayName = _getDayName(_editDayIndex);
    final lessons = _timetableData[dayName] ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('時間割編集', style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (index) {
                final isSelected = _editDayIndex == index;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[200],
                        foregroundColor: isSelected ? Colors.white : Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      onPressed: () => setState(() => _editDayIndex = index),
                      child: Text(_getDayName(index), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lessons.length,
              itemBuilder: (context, index) {
                final lesson = lessons[index];
                return LessonEditCard(
                  key: ValueKey("$dayName-${lesson['period']}"),
                  lesson: lesson,
                  onSave: (updatedLesson) {
                    setState(() {
                      _timetableData[dayName]![index] = updatedLesson;
                    });
                    _saveTimetableData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${lesson['period']}を保存しました！')),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 3. 課題管理タブ ====================
  Widget _buildAssignmentTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('課題・ToDo', style: TextStyle(fontWeight: FontWeight.bold))),
      body: _assignments.isEmpty
          ? const Center(child: Text('現在、未提出の課題はありません！✨'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _assignments.length,
              itemBuilder: (context, index) {
                final task = _assignments[index];
                final bool isDone = task['isCompleted'] ?? false;
                return Card(
                  elevation: isDone ? 0 : 2,
                  color: isDone ? Colors.grey[200] : Colors.white,
                  child: ListTile(
                    leading: Checkbox(
                      value: isDone,
                      onChanged: (bool? value) {
                        setState(() => _assignments[index]['isCompleted'] = value);
                        _saveAssignments();
                      },
                    ),
                    title: Text(
                      task['title'],
                      style: TextStyle(decoration: isDone ? TextDecoration.lineThrough : null, color: isDone ? Colors.grey : Colors.black87, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("科目: ${task['subject']}  |  締切: ${task['dueDate']}"),
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
        child: const Icon(Icons.add_task),
      ),
    );
  }

  void _showAddAssignmentDialog() {
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1)); 

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String dateStr = _formatDate(selectedDate);
          return AlertDialog(
            title: const Text('新しい課題を追加'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '課題内容')),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(labelText: '対象科目', hintText: '入力で次回授業日を自動検索', hintStyle: TextStyle(fontSize: 12)),
                  onChanged: (val) {
                    DateTime? nextDate = _findNextClassDate(val);
                    if (nextDate != null) setDialogState(() => selectedDate = nextDate);
                  },
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("締切: $dateStr", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ElevatedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setDialogState(() => selectedDate = picked);
                      },
                      child: const Text('変更'),
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
                      'dueDate': _formatDate(selectedDate),
                      'isCompleted': false,
                    });
                  });
                  _saveAssignments();
                  Navigator.pop(context);
                },
                child: const Text('追加'),
              ),
            ],
          );
        }
      ),
    );
  }

  // ==================== 4. A/B表（週日程設定）タブ ====================
  Widget _buildConfigTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('A/B表・週日程設定', style: TextStyle(fontWeight: FontWeight.bold))),
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
                            setState(() {
                              config.weekType = config.weekType == 'A' ? 'B' : (config.weekType == 'B' ? '休' : 'A');
                            });
                            _saveDayConfigs();
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            height: 60,
                            decoration: BoxDecoration(
                              color: config.weekType == 'A' ? Colors.blue[100] : (config.weekType == 'B' ? Colors.green[100] : Colors.grey[300]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("${targetDate.month}/${targetDate.day}", style: const TextStyle(fontSize: 10)),
                                Text(_getDayName(dayIndex), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                Text(config.weekType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

// ==================== 編集用カスタムカード（授業名もA/B週で完全分離） ====================
class LessonEditCard extends StatefulWidget {
  final Map<String, String> lesson;
  final Function(Map<String, String>) onSave;

  const LessonEditCard({super.key, required this.lesson, required this.onSave});

  @override
  State<LessonEditCard> createState() => _LessonEditCardState();
}

class _LessonEditCardState extends State<LessonEditCard> {
  late TextEditingController _subjectACtrl;
  late TextEditingController _teacherACtrl;
  late TextEditingController _roomACtrl;
  late TextEditingController _subjectBCtrl;
  late TextEditingController _teacherBCtrl;
  late TextEditingController _roomBCtrl;
  late bool _isAlternate;

  @override
  void initState() {
    super.initState();
    // 互換性を保ちつつ、A週・B週それぞれに授業名を割り当て
    _subjectACtrl = TextEditingController(text: widget.lesson['subjectA'] ?? widget.lesson['subject']);
    _teacherACtrl = TextEditingController(text: widget.lesson['teacherA']);
    _roomACtrl = TextEditingController(text: widget.lesson['roomA']);
    _subjectBCtrl = TextEditingController(text: widget.lesson['subjectB']);
    _teacherBCtrl = TextEditingController(text: widget.lesson['teacherB']);
    _roomBCtrl = TextEditingController(text: widget.lesson['roomB']);
    _isAlternate = widget.lesson['isAlternate'] == 'true';
  }

  @override
  void dispose() {
    _subjectACtrl.dispose();
    _teacherACtrl.dispose();
    _roomACtrl.dispose();
    _subjectBCtrl.dispose();
    _teacherBCtrl.dispose();
    _roomBCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.lesson['period']!,
                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),

            // 隔週設定じゃない場合（通常の一体型入力）
            if (!_isAlternate) ...[
              TextField(
                controller: _subjectACtrl,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: '授業名',
                  labelStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teacherACtrl,
                      decoration: const InputDecoration(labelText: '担当教員', border: UnderlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _roomACtrl,
                      decoration: const InputDecoration(labelText: '教室', border: UnderlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // 隔週設定の場合：授業名も含めてA週・B週を完全に分離！
              const Row(
                children: [
                  Icon(Icons.looks_one, color: Colors.blue, size: 20),
                  SizedBox(width: 6),
                  Text('A週の授業設定', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _subjectACtrl,
                decoration: const InputDecoration(labelText: '授業名 (A週)', border: UnderlineInputBorder()),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teacherACtrl,
                      decoration: const InputDecoration(labelText: '担当教員 (A週)', border: UnderlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _roomACtrl,
                      decoration: const InputDecoration(labelText: '教室 (A週)', border: UnderlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Row(
                children: [
                  Icon(Icons.looks_two, color: Colors.green, size: 20),
                  SizedBox(width: 6),
                  Text('B週の授業設定', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _subjectBCtrl,
                decoration: const InputDecoration(labelText: '授業名 (B週)', border: UnderlineInputBorder()),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teacherBCtrl,
                      decoration: const InputDecoration(labelText: '担当教員 (B週)', border: UnderlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _roomBCtrl,
                      decoration: const InputDecoration(labelText: '教室 (B週)', border: UnderlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _isAlternate,
                      onChanged: (val) {
                        setState(() {
                          _isAlternate = val ?? false;
                        });
                      },
                    ),
                    const Text('隔週', style: TextStyle(fontSize: 14)),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[50],
                    foregroundColor: Colors.blue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final updated = {
                      'period': widget.lesson['period']!,
                      'subjectA': _subjectACtrl.text,
                      'teacherA': _teacherACtrl.text,
                      'roomA': _roomACtrl.text,
                      'subjectB': _isAlternate ? _subjectBCtrl.text : '',
                      'teacherB': _isAlternate ? _teacherBCtrl.text : '',
                      'roomB': _isAlternate ? _roomBCtrl.text : '',
                      'isAlternate': _isAlternate ? 'true' : 'false',
                    };
                    widget.onSave(updated);
                  },
                  child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}