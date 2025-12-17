import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSecrets.ensureLoaded();
  runApp(const RemindApp());
}

class AppThemeSetting {
  const AppThemeSetting({
    required this.seedColor,
  });

  final Color seedColor;

  AppThemeSetting copyWith({Color? seedColor}) {
    return AppThemeSetting(
      seedColor: seedColor ?? this.seedColor,
    );
  }

  ThemeData _buildTheme() {
    final colorScheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light);
    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.light,
    );
    return base.copyWith(
      scaffoldBackgroundColor: Colors.grey.shade50,
      textTheme: base.textTheme.apply(
        bodyColor: Colors.grey.shade900,
        displayColor: Colors.grey.shade900,
      ),
    );
  }

  ThemeData get lightTheme => _buildTheme();
}

const AppThemeSetting _defaultTheme = AppThemeSetting(
  seedColor: Colors.indigo,
);

class ReminderSettings {
  const ReminderSettings({
    required this.enableDailyReminder,
    required this.dailyReminderTime,
    required this.leadMinutes,
    required this.enableQuietHours,
    required this.quietStart,
    required this.quietEnd,
  });

  factory ReminderSettings.defaults() => ReminderSettings(
        enableDailyReminder: true,
        dailyReminderTime: const TimeOfDay(hour: 21, minute: 0),
        leadMinutes: 30,
        enableQuietHours: true,
        quietStart: const TimeOfDay(hour: 23, minute: 0),
        quietEnd: const TimeOfDay(hour: 7, minute: 0),
      );

  final bool enableDailyReminder;
  final TimeOfDay dailyReminderTime;
  final int leadMinutes;
  final bool enableQuietHours;
  final TimeOfDay quietStart;
  final TimeOfDay quietEnd;

  ReminderSettings copyWith({
    bool? enableDailyReminder,
    TimeOfDay? dailyReminderTime,
    int? leadMinutes,
    bool? enableQuietHours,
    TimeOfDay? quietStart,
    TimeOfDay? quietEnd,
  }) {
    return ReminderSettings(
      enableDailyReminder: enableDailyReminder ?? this.enableDailyReminder,
      dailyReminderTime: dailyReminderTime ?? this.dailyReminderTime,
      leadMinutes: leadMinutes ?? this.leadMinutes,
      enableQuietHours: enableQuietHours ?? this.enableQuietHours,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
    );
  }

  Map<String, dynamic> toJson() => {
        'enableDailyReminder': enableDailyReminder,
        'dailyReminderMinutes': _timeOfDayToMinutes(dailyReminderTime),
        'leadMinutes': leadMinutes,
        'enableQuietHours': enableQuietHours,
        'quietStartMinutes': _timeOfDayToMinutes(quietStart),
        'quietEndMinutes': _timeOfDayToMinutes(quietEnd),
      };

  static ReminderSettings? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    try {
      return ReminderSettings(
        enableDailyReminder: map['enableDailyReminder'] as bool? ?? true,
        dailyReminderTime: _minutesToTimeOfDay(map['dailyReminderMinutes'] as int? ?? 1260),
        leadMinutes: map['leadMinutes'] as int? ?? 30,
        enableQuietHours: map['enableQuietHours'] as bool? ?? true,
        quietStart: _minutesToTimeOfDay(map['quietStartMinutes'] as int? ?? 1380),
        quietEnd: _minutesToTimeOfDay(map['quietEndMinutes'] as int? ?? 420),
      );
    } catch (_) {
      return ReminderSettings.defaults();
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReminderSettings &&
        other.enableDailyReminder == enableDailyReminder &&
        other.dailyReminderTime == dailyReminderTime &&
        other.leadMinutes == leadMinutes &&
        other.enableQuietHours == enableQuietHours &&
        other.quietStart == quietStart &&
        other.quietEnd == quietEnd;
  }

  @override
  int get hashCode => Object.hash(
        enableDailyReminder,
        dailyReminderTime,
        leadMinutes,
        enableQuietHours,
        quietStart,
        quietEnd,
      );
}

int _timeOfDayToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

TimeOfDay _minutesToTimeOfDay(int minutes) {
  final normalized = minutes % (24 * 60);
  final hour = normalized ~/ 60;
  final minute = normalized % 60;
  return TimeOfDay(hour: hour, minute: minute);
}


class RemindApp extends StatefulWidget {
  const RemindApp({super.key});

  @override
  State<RemindApp> createState() => _RemindAppState();
}

class _RemindAppState extends State<RemindApp> {
  AppThemeSetting _themeSetting = _defaultTheme;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('theme_seed');
    AppThemeSetting setting = _defaultTheme;
    if (colorValue != null) {
      setting = setting.copyWith(seedColor: Color(colorValue));
    }
    if (!mounted) return;
    setState(() {
      _themeSetting = setting;
    });
  }

  Future<void> _updateTheme(AppThemeSetting setting) async {
    setState(() {
      _themeSetting = setting;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_seed', setting.seedColor.value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '复习提醒助手',
      theme: _themeSetting.lightTheme,
      themeMode: ThemeMode.light,
      home: HomeShell(
        themeSetting: _themeSetting,
        onThemeChanged: _updateTheme,
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.themeSetting,
    required this.onThemeChanged,
  });

  final AppThemeSetting themeSetting;
  final ValueChanged<AppThemeSetting> onThemeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  late ScheduleService _scheduleService;
  late Future<WeeklyScheduleOverview> _overviewFuture;
  late ScheduleRepository _repository;
  final GlobalKey<AgendaTabState> _agendaKey = GlobalKey<AgendaTabState>();
  DateTime? _termStartDate;
  DateTime _displayedWeekAnchor = DateTime.now();
  static const String _lessonSummaryPrefKey = 'lesson_summaries';
  static const String _lessonHighlightPrefKey = 'lesson_highlights';
  static const String _userLessonsPrefKey = 'user_lessons';
  static const String _reviewTaskPrefKey = 'review_tasks';
  static const String _reminderSettingsPrefKey = 'reminder_settings';
  final Map<String, String> _lessonSummaries = {};
  final Map<String, String> _lessonHighlights = {};
  final Set<String> _aiProcessingLessons = {};
  final Map<String, List<ReviewTask>> _reviewPlans = {};
  final Set<String> _reviewPlanningLessons = {};
  ReminderSettings _reminderSettings = ReminderSettings.defaults();

  @override
  void initState() {
    super.initState();
    ReminderService.instance.ensureInitialized();
    _displayedWeekAnchor = DateTime.now();
    _repository = MockScheduleRepository();
    _scheduleService = ScheduleService(
      repository: _repository,
      reviewTaskProvider: _reviewTasksForDate,
      enableAutoReviewPlan: false,
    );
    _overviewFuture = _scheduleService.loadWeekOverview(_displayedWeekAnchor);
    _loadTermStartDate();
    _loadLessonHighlights();
    _loadLessonSummaries();
    _loadReviewPlans();
    _loadPersistedLessons();
    _loadReminderSettings();
  }

  void _reload() {
    _loadWeek(_displayedWeekAnchor);
  }

  Future<void> _applyImportedLessons(List<Lesson> lessons) async {
    await _persistLessons(lessons);
    _useLessonRepository(lessons, showSnack: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('成功导入${lessons.length}条课程，已替换课表'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _useLessonRepository(List<Lesson> lessons, {bool showSnack = true}) {
    setState(() {
      _repository = MemoryScheduleRepository(lessons: lessons);
      _scheduleService = ScheduleService(
        repository: _repository,
        reviewTaskProvider: _reviewTasksForDate,
        enableAutoReviewPlan: false,
      );
    });
    _loadWeek(_displayedWeekAnchor);
    setState(() {
      _currentIndex = 0;
    });
    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换到用户课程表，共${lessons.length}条课程'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _loadWeek(DateTime anchor) {
    setState(() {
      _displayedWeekAnchor = anchor;
      _overviewFuture = _scheduleService.loadWeekOverview(anchor);
    });
  }

  void _shiftWeek(int delta) {
    final anchor = _displayedWeekAnchor.add(Duration(days: delta * 7));
    _loadWeek(anchor);
  }

  void _resetToCurrentWeek() {
    _loadWeek(DateTime.now());
  }

  List<ReviewTask> _reviewTasksForDate(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    return _reviewPlans.values.expand((tasks) => tasks).where((task) => _isSameDay(task.scheduledAt, target)).toList();
  }

  void _removeReviewTaskByKey(String key) async {
    bool changed = false;
    setState(() {
      final keysToRemove = <String>[];
      _reviewPlans.forEach((lessonKey, tasks) {
        final before = tasks.length;
        tasks.removeWhere((task) => reviewTaskStorageKey(task) == key);
        final removed = before != tasks.length;
        if (removed) {
          changed = true;
        }
        if (tasks.isEmpty) {
          keysToRemove.add(lessonKey);
        }
      });
      for (final lessonKey in keysToRemove) {
        _reviewPlans.remove(lessonKey);
      }
    });
    if (changed) {
      await _persistReviewPlans();
      _reload();
    }
  }

  List<Widget> _buildAppBarActions() {
    if (_currentIndex == 0) {
      return [
        IconButton(
          onPressed: () => _shiftWeek(-1),
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一周',
        ),
        TextButton(
          onPressed: _resetToCurrentWeek,
          child: const Text('本周'),
        ),
        IconButton(
          onPressed: () => _shiftWeek(1),
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一周',
        ),
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: '刷新数据'),
      ];
    }
    if (_currentIndex != 2) {
      return [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: '刷新数据')];
    }
    return const [];
  }

  String _formatWeekRangeLabel(List<WeekDayLessons> days) {
    if (days.isEmpty) return '';
    final first = days.first.date;
    final last = days.last.date;
    final range = '${first.month}/${first.day} - ${last.month}/${last.day}';
    return range;
  }

  Future<void> _openWebImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => WebImportPage(
          onImported: _applyImportedLessons,
          termStartDate: _termStartDate,
        ),
      ),
    );
  }

  Future<void> _loadLessonSummaries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lessonSummaryPrefKey);
      if (raw == null) return;
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (!mounted) return;
      setState(() {
        _lessonSummaries
          ..clear()
          ..addEntries(decoded.entries.map((e) => MapEntry(e.key, e.value.toString())));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('课程要点读取失败：$e')),
      );
    }
  }

  Future<void> _persistLessonSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lessonSummaryPrefKey, jsonEncode(_lessonSummaries));
  }

  Future<void> _loadPersistedLessons() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userLessonsPrefKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final lessons = decoded
          .map((e) => Lesson.fromJson(Map<String, dynamic>.from(e as Map)))
          .whereType<Lesson>()
          .toList();
      if (lessons.isEmpty) return;
      if (!mounted) return;
      _useLessonRepository(lessons, showSnack: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('用户课程加载失败：$e')),
      );
    }
  }

  Future<void> _persistLessons(List<Lesson> lessons) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _userLessonsPrefKey,
      jsonEncode(lessons.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _loadLessonHighlights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lessonHighlightPrefKey);
      if (raw == null) return;
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (!mounted) return;
      setState(() {
        _lessonHighlights
          ..clear()
          ..addEntries(decoded.entries.map((e) => MapEntry(e.key, e.value.toString())));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 摘要读取失败：$e')),
      );
    }
  }

  Future<void> _loadReminderSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_reminderSettingsPrefKey);
      if (raw == null) return;
      final json = jsonDecode(raw);
      final settings = ReminderSettings.fromJson(json);
      if (settings == null) return;
      if (!mounted) return;
      setState(() {
        _reminderSettings = settings;
      });
    } catch (_) {
      // ignore malformed
    }
  }

  Future<void> _saveReminderSettings(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reminderSettingsPrefKey, jsonEncode(settings.toJson()));
  }

  Future<void> _updateReminderSettings(ReminderSettings settings) async {
    setState(() {
      _reminderSettings = settings;
    });
    await _saveReminderSettings(settings);
    await _syncReviewReminders();
    final agendaState = _agendaKey.currentState;
    if (agendaState != null) {
      await agendaState.resyncManualReminders(settings);
    }
  }

  Future<void> _syncReviewReminders() async {
    await ReminderService.instance.syncReviewTasks(
      settings: _reminderSettings,
      tasks: _reviewPlans.values.expand((e) => e),
    );
  }

  Future<void> _loadReviewPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reviewTaskPrefKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      final tasks = <ReviewTask>[];
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is Map) {
            final parsed = ReviewTask.fromJson(Map<String, dynamic>.from(entry));
            if (parsed != null) tasks.add(parsed);
          }
        }
      } else if (decoded is Map) {
        for (final value in decoded.values) {
          if (value is List) {
            for (final entry in value) {
              if (entry is Map) {
                final parsed = ReviewTask.fromJson(Map<String, dynamic>.from(entry));
                if (parsed != null) tasks.add(parsed);
              }
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _reviewPlans
          ..clear()
          ..addAll(_groupReviewTasksByLesson(tasks));
      });
      _reload();
      await _syncReviewReminders();
    } catch (e) {
      await prefs.remove(_reviewTaskPrefKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('复习计划读取失败，已清除旧数据：$e')),
      );
    }
  }

  Map<String, List<ReviewTask>> _groupReviewTasksByLesson(List<ReviewTask> tasks) {
    final map = <String, List<ReviewTask>>{};
    for (final task in tasks) {
      final key = task.lessonKey.isNotEmpty ? task.lessonKey : '_misc';
      map.putIfAbsent(key, () => []).add(task);
    }
    for (final entry in map.entries) {
      entry.value.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    }
    return map;
  }

  Future<void> _persistReviewPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final flattened = _reviewPlans.values.expand((e) => e).map((e) => e.toJson()).toList();
    await prefs.setString(_reviewTaskPrefKey, jsonEncode(flattened));
    await _syncReviewReminders();
  }

  Future<void> _persistLessonHighlights() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lessonHighlightPrefKey, jsonEncode(_lessonHighlights));
  }

  Future<void> _loadTermStartDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt('term_start_date');
      if (!mounted) return;
      setState(() {
        _termStartDate = millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开学日期读取失败：$e')),
      );
    }
  }

  Future<void> _openLessonCapture(Lesson lesson) async {
    final key = lessonStorageKey(lesson);
    final initial = _lessonSummaries[key];
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (ctx) => LessonCapturePage(
          lesson: lesson,
          initialSummary: initial,
        ),
      ),
    );
    if (!mounted) return;
    final trimmed = result?.trim();
    if (trimmed == null) return;
    if (trimmed.isEmpty) {
      setState(() {
        _lessonSummaries.remove(key);
      });
      await _persistLessonSummaries();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除课程要点')),
      );
      return;
    }
    setState(() {
      _lessonSummaries[key] = trimmed;
      _lessonHighlights.remove(key);
    });
    await _persistLessonSummaries();
    await _persistLessonHighlights();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已获取原始内容，开始分析「${lesson.courseName}」')),
    );
    _analyzeLessonWithAi(key, lesson, trimmed);
  }

  void _triggerAiAnalysis(Lesson lesson) {
    final key = lessonStorageKey(lesson);
    final raw = _lessonSummaries[key];
    if (raw == null || raw.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先抓取原始内容，再使用 AI 提炼')),
      );
      return;
    }
    _analyzeLessonWithAi(key, lesson, raw);
  }

  Future<void> _generateReviewPlan(Lesson lesson) async {
    final lessonKey = lessonStorageKey(lesson);
    final aiSummary = _lessonHighlights[lessonKey]?.trim();
    final rawContent = _lessonSummaries[lessonKey]?.trim();
    final source = (aiSummary != null && aiSummary.isNotEmpty)
        ? aiSummary
        : rawContent != null && rawContent.isNotEmpty
            ? rawContent
            : null;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先抓取并完成 AI 提炼后再生成复习日程')),
      );
      return;
    }
    if (_reviewPlanningLessons.contains(lessonKey)) return;
    setState(() {
      _reviewPlanningLessons.add(lessonKey);
    });
    try {
      final suggestions = await LessonReviewPlanGenerator.instance.generate(lesson, source);
      final tasks = await _scheduleReviewTasks(lesson, suggestions);
      if (!mounted) return;
      setState(() {
        if (tasks.isEmpty) {
          _reviewPlans.remove(lessonKey);
        } else {
          _reviewPlans[lessonKey] = tasks;
        }
      });
      await _persistReviewPlans();
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成${tasks.length}条复习日程')),
      );
    } on LessonAiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成复习日程失败：${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成复习日程异常：$e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _reviewPlanningLessons.remove(lessonKey);
      });
    }
  }

  Future<List<ReviewTask>> _scheduleReviewTasks(
    Lesson lesson,
    List<ReviewPlanSuggestion> suggestions,
  ) async {
    if (suggestions.isEmpty) return [];
    final lessonKey = lessonStorageKey(lesson);
    final cache = <int, List<Lesson>>{};
    final results = <ReviewTask>[];
    final occupied = _reviewPlans.entries
        .where((entry) => entry.key != lessonKey)
        .expand((entry) => entry.value)
        .toList();
    final baseTime = lesson.endTime;
    for (var i = 0; i < suggestions.length; i++) {
      final suggestion = suggestions[i];
      final interval = _intervalForSuggestion(i);
      var desired = baseTime.add(interval);
      desired = await _findAvailableReviewSlot(desired, Duration(minutes: suggestion.durationMinutes), cache, occupied);
      final offset = desired.difference(lesson.endTime);
      final task = ReviewTask(
        courseName: lesson.courseName,
        scheduledAt: desired,
        offsetFromLesson: offset,
        focus: suggestion.topic,
        note: suggestion.tip,
        method: suggestion.method,
        durationMinutes: suggestion.durationMinutes,
        lessonKey: lessonKey,
        aiAdvice: suggestion.tip,
      );
      results.add(task);
      occupied.add(task);
    }
    results.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return results;
  }

  Duration _intervalForSuggestion(int index) {
    if (index < kReviewPlanIntervals.length) return kReviewPlanIntervals[index];
    final extraWeeks = index - kReviewPlanIntervals.length + 1;
    return kReviewPlanIntervals.last + Duration(days: extraWeeks * 7);
  }

  Future<DateTime> _findAvailableReviewSlot(
    DateTime desiredStart,
    Duration duration,
    Map<int, List<Lesson>> lessonCache,
    List<ReviewTask> occupied,
  ) async {
    DateTime start = desiredStart;
    for (var attempt = 0; attempt < 24; attempt++) {
      final normalizedDay = DateTime(start.year, start.month, start.day);
      final cacheKey = normalizedDay.millisecondsSinceEpoch;
      List<Lesson> lessons;
      if (lessonCache.containsKey(cacheKey)) {
        lessons = lessonCache[cacheKey]!;
      } else {
        lessons = await _repository.fetchLessonsForDate(normalizedDay);
        lessonCache[cacheKey] = lessons;
      }
      var end = start.add(duration);
      final restWindow = _findRestOverlap(start, end);
      if (restWindow != null) {
        start = restWindow.end.add(const Duration(minutes: 5));
        continue;
      }
      end = start.add(duration);
      final hasLessonConflict = lessons.any(
        (l) {
          final bufferedStart = l.startTime.subtract(kScheduleBuffer);
          final bufferedEnd = l.endTime.add(kScheduleBuffer);
          return _timeOverlap(bufferedStart, bufferedEnd, start, end);
        },
      );
      final hasTaskConflict = occupied.any((task) {
        final tStart = task.scheduledAt.subtract(kScheduleBuffer);
        final tEnd = task.scheduledAt.add(Duration(minutes: task.durationMinutes)).add(kScheduleBuffer);
        return _timeOverlap(tStart, tEnd, start, end);
      });
      if (!hasLessonConflict && !hasTaskConflict) {
        return start;
      }
      start = start.add(const Duration(minutes: 45));
    }
    return desiredStart;
  }

  Future<void> _analyzeLessonWithAi(String key, Lesson lesson, String raw) async {
    if (_aiProcessingLessons.contains(key)) return;
    setState(() {
      _aiProcessingLessons.add(key);
    });
    try {
      final summary = await LessonAiSummarizer.instance.summarize(lesson, raw);
      if (!mounted) return;
      setState(() {
        _lessonHighlights[key] = summary.trim();
      });
      await _persistLessonHighlights();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 已完成「${lesson.courseName}」的要点提炼')),
      );
    } on LessonAiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 提炼失败：${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 提炼异常：$e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _aiProcessingLessons.remove(key);
      });
    }
  }

  Future<void> _saveTermStartDate(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('term_start_date', normalized.millisecondsSinceEpoch);
      if (!mounted) return;
      setState(() {
        _termStartDate = normalized;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已设置开学日期为 ${normalized.month}/${normalized.day}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存开学日期失败：$e')),
      );
    }
  }

  Future<void> _pickTermStartDate(BuildContext context) async {
    final initial = _termStartDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 1),
    );
    if (picked != null) {
      await _saveTermStartDate(picked);
    }
  }

  int? _weekNumberFor(DateTime anchor) {
    if (_termStartDate == null) return null;
    final normalizedStart = DateTime(_termStartDate!.year, _termStartDate!.month, _termStartDate!.day);
    final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
    final diff = monday.difference(normalizedStart);
    final week = diff.inDays ~/ 7 + 1;
    return week <= 0 ? 1 : week;
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['课程表', '日程', '用户'];
    return FutureBuilder<WeeklyScheduleOverview>(
      future: _overviewFuture,
      builder: (context, snapshot) {
        final gradientBackground = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.08),
                Theme.of(context).colorScheme.secondary.withOpacity(0.06),
              ],
            ),
          ),
        );

        final appBarTitle = _currentIndex == 0
            ? Text('课程表 · ${_weekNumberFor(_displayedWeekAnchor) != null ? '第${_weekNumberFor(_displayedWeekAnchor)}周' : '尚未设置开学日期'}')
            : Text(titles[_currentIndex]);

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: appBarTitle,
              actions: _buildAppBarActions(),
            ),
            body: Stack(children: [gradientBackground, const Center(child: CircularProgressIndicator())]),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: appBarTitle,
              actions: _buildAppBarActions(),
            ),
            body: Stack(
              children: [
                gradientBackground,
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      const Text('数据加载失败，请稍后再试'),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _reload, child: const Text('重新获取')),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final overview = snapshot.data!;
        final weekNumber = _weekNumberFor(_displayedWeekAnchor);
        final pages = [
          TimetableTab(
            weekDays: overview.weekDays,
            currentWeekNumber: weekNumber,
            termStartDate: _termStartDate,
            onCaptureLesson: _openLessonCapture,
            lessonSummaries: _lessonSummaries,
            lessonHighlights: _lessonHighlights,
            processingLessons: _aiProcessingLessons,
            onRequestAiAnalysis: _triggerAiAnalysis,
            reviewPlans: _reviewPlans,
            planningLessons: _reviewPlanningLessons,
            onGenerateReviewPlan: _generateReviewPlan,
          ),
          AgendaTab(
            key: _agendaKey,
            items: overview.scheduleItems,
            currentDate: _displayedWeekAnchor,
            onDateChange: (date) => _loadWeek(date),
            onDeleteAutoTask: _removeReviewTaskByKey,
            reminderSettings: _reminderSettings,
          ),
          UserTab(
            onOpenImport: _openWebImport,
            onPickTermStart: () => _pickTermStartDate(context),
            termStartDate: _termStartDate,
            themeSetting: widget.themeSetting,
            onThemeChanged: widget.onThemeChanged,
            reminderSettings: _reminderSettings,
            onReminderChanged: _updateReminderSettings,
          ),
        ];

        String? startLabel;
        if (_termStartDate != null) {
          startLabel =
              '${_termStartDate!.year}-${_termStartDate!.month.toString().padLeft(2, '0')}-${_termStartDate!.day.toString().padLeft(2, '0')}';
        }
        final weekTitle = weekNumber != null ? '第$weekNumber周' : '尚未设置开学日期';

        return Scaffold(
          appBar: AppBar(
            title: _currentIndex == 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(weekTitle, style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        '${_formatWeekRangeLabel(overview.weekDays)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (startLabel != null)
                        Text(
                          '开学日：$startLabel',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  )
                : Text(titles[_currentIndex]),
            actions: _buildAppBarActions(),
          ),
          body: Stack(
            children: [
              gradientBackground,
              SafeArea(child: IndexedStack(index: _currentIndex, children: pages)),
            ],
          ),
          floatingActionButton: _currentIndex == 1
              ? FloatingActionButton.extended(
                  onPressed: () => _agendaKey.currentState?.createSchedule(context),
                  icon: const Icon(Icons.add),
                  label: const Text('添加日程'),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
              if (index == 0) {
                _loadTermStartDate();
              }
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.calendar_view_week_outlined), label: '课程表'),
              NavigationDestination(icon: Icon(Icons.event_note_outlined), label: '日程'),
              NavigationDestination(icon: Icon(Icons.person_outline), label: '用户'),
            ],
          ),
        );
      },
    );
  }
}

class TimetableTab extends StatelessWidget {
  const TimetableTab({
    super.key,
    required this.weekDays,
    this.currentWeekNumber,
    this.termStartDate,
    required this.onCaptureLesson,
    required this.lessonSummaries,
    required this.lessonHighlights,
    required this.processingLessons,
    required this.onRequestAiAnalysis,
    required this.reviewPlans,
    required this.planningLessons,
    required this.onGenerateReviewPlan,
  });

  final List<WeekDayLessons> weekDays;
  final int? currentWeekNumber;
  final DateTime? termStartDate;
  final ValueChanged<Lesson> onCaptureLesson;
  final Map<String, String> lessonSummaries;
  final Map<String, String> lessonHighlights;
  final Set<String> processingLessons;
  final ValueChanged<Lesson> onRequestAiAnalysis;
  final Map<String, List<ReviewTask>> reviewPlans;
  final Set<String> planningLessons;
  final ValueChanged<Lesson> onGenerateReviewPlan;

  @override
  Widget build(BuildContext context) {
    const double timeColumnWidth = 84;
    const double slotHeight = 84;
    const double pagePadding = 16;
    const double minDayColumnWidth = 110;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final dayCount = weekDays.isEmpty ? 1 : weekDays.length;
        final available = (screenWidth - pagePadding * 2 - timeColumnWidth).clamp(0, double.infinity);
        final fittedWidth = available / dayCount;
        final dayColumnWidth = fittedWidth < minDayColumnWidth ? minDayColumnWidth : fittedWidth;
        final tableWidth = timeColumnWidth + dayColumnWidth * dayCount;
        final needsHorizontal = tableWidth + pagePadding * 2 > screenWidth;
        final table = Padding(
          padding: const EdgeInsets.symmetric(horizontal: pagePadding),
          child: SizedBox(
            width: tableWidth,
            child: _TimetableContent(
              weekDays: weekDays,
              timeColumnWidth: timeColumnWidth,
              dayColumnWidth: dayColumnWidth,
              slotHeight: slotHeight,
              currentWeekNumber: currentWeekNumber,
              onCaptureLesson: onCaptureLesson,
              lessonSummaries: lessonSummaries,
              lessonHighlights: lessonHighlights,
              processingLessons: processingLessons,
              onRequestAiAnalysis: onRequestAiAnalysis,
              reviewPlans: reviewPlans,
              planningLessons: planningLessons,
              onGenerateReviewPlan: onGenerateReviewPlan,
            ),
          ),
        );

        final Widget body = needsHorizontal
            ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)
            : Center(child: table);

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: body,
        );
      },
    );
  }
}

class _TimetableContent extends StatelessWidget {
  const _TimetableContent({
    required this.weekDays,
    required this.timeColumnWidth,
    required this.dayColumnWidth,
    required this.slotHeight,
    this.currentWeekNumber,
    required this.onCaptureLesson,
    required this.lessonSummaries,
    required this.lessonHighlights,
    required this.processingLessons,
    required this.onRequestAiAnalysis,
    required this.reviewPlans,
    required this.planningLessons,
    required this.onGenerateReviewPlan,
  });

  final List<WeekDayLessons> weekDays;
  final double timeColumnWidth;
  final double dayColumnWidth;
  final double slotHeight;
  final int? currentWeekNumber;
  final ValueChanged<Lesson> onCaptureLesson;
  final Map<String, String> lessonSummaries;
  final Map<String, String> lessonHighlights;
  final Set<String> processingLessons;
  final ValueChanged<Lesson> onRequestAiAnalysis;
  final Map<String, List<ReviewTask>> reviewPlans;
  final Set<String> planningLessons;
  final ValueChanged<Lesson> onGenerateReviewPlan;
  @override
  Widget build(BuildContext context) {
    final totalHeight = slotHeight * kTimeSlots.length;
    final headerStyle = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);
    final dateStyle = Theme.of(context).textTheme.bodySmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: timeColumnWidth),
            ...weekDays.map((day) {
              final label = _weekdayLabel(day.date.weekday);
              final dateText = '${day.date.month}/${day.date.day}';
              return SizedBox(
                width: dayColumnWidth,
                child: Column(
                  children: [
                    Text(label, style: headerStyle),
                    const SizedBox(height: 4),
                    Text(dateText, style: dateStyle),
                  ],
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: timeColumnWidth,
              height: totalHeight,
              child: Column(
                children: kTimeSlots
                    .map(
                      (slot) => SizedBox(
                        height: slotHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(slot.label, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(slot.timeRange, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            SizedBox(
              width: dayColumnWidth * weekDays.length,
              height: totalHeight,
              child: Stack(
                children: [
                  for (var dayIndex = 0; dayIndex < weekDays.length; dayIndex++)
                    for (var i = 0; i < kTimeSlots.length; i++)
                      Positioned(
                        left: dayIndex * dayColumnWidth,
                        top: i * slotHeight,
                        child: Container(
                          width: dayColumnWidth,
                          height: slotHeight,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200, width: 1),
                          ),
                        ),
                      ),
                  for (var dayIndex = 0; dayIndex < weekDays.length; dayIndex++)
                    ...weekDays[dayIndex].lessons.map((lesson) {
                      final span = _lessonSpan(lesson, weekDays[dayIndex].date);
                      if (span == null) return const SizedBox.shrink();
                      final baseColor = _courseColor(lesson.courseName);
                      final top = (span.startIndex - 1) * slotHeight + 4;
                      final height = span.slotCount * slotHeight - 8;
                      final textTheme = Theme.of(context).textTheme;
                      final key = lessonStorageKey(lesson);
                      final storedHighlight = lessonHighlights[key]?.trim();
                      final hasHighlight = storedHighlight != null && storedHighlight.isNotEmpty;
                      final storedRaw = lessonSummaries[key]?.trim();
                      final hasCapturedSummary = storedRaw != null && storedRaw.isNotEmpty;
                      final bool isProcessing = processingLessons.contains(key);
                      final remark = hasHighlight
                          ? '已抓取并完成 AI 提炼'
                          : hasCapturedSummary
                              ? (isProcessing ? '已抓取内容，AI 分析中…' : '已抓取内容，等待 AI 提炼')
                              : _formatLessonRemark(lesson.topic);
                      final bool isActive = currentWeekNumber == null
                          ? true
                          : (lesson.weekPattern?.isActive(currentWeekNumber!) ?? true);
                      final fillColor = baseColor.withOpacity(isActive ? 0.22 : 0.08);
                      final borderColor = baseColor.withOpacity(isActive ? 0.55 : 0.25);
                      final titleColor = isActive ? Colors.black87 : Colors.black45;
                      final infoColor = isActive ? Colors.black87 : Colors.black45;
                      final teacherColor = isActive ? Colors.black54 : Colors.black38;
                      final weekDesc = lesson.weekPattern?.description();
                      return Positioned(
                        left: dayIndex * dayColumnWidth + 6,
                        top: top,
                        width: dayColumnWidth - 12,
                        height: height,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showLessonDetail(
                              context,
                              lesson,
                              isActive,
                              storedRaw,
                              storedHighlight,
                              isProcessing,
                              onCaptureLesson,
                              onRequestAiAnalysis,
                              reviewPlans,
                              planningLessons,
                              onGenerateReviewPlan,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: fillColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor, width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: baseColor.withOpacity(isActive ? 0.18 : 0.08),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lesson.courseName,
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: titleColor,
                                    ),
                                    maxLines: 3,
                                    softWrap: true,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatTime(lesson.startTime)} - ${_formatTime(lesson.endTime)}',
                                    style: textTheme.bodySmall?.copyWith(fontSize: 11, color: infoColor),
                                    maxLines: 2,
                                    softWrap: true,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    lesson.location,
                                    style: textTheme.bodySmall?.copyWith(fontSize: 11, color: infoColor),
                                    maxLines: 2,
                                    softWrap: true,
                                  ),
                                  const SizedBox(height: 2),
                                  if (lesson.teacher.trim().isNotEmpty)
                                    Text(
                                      '教师：${lesson.teacher}',
                                      style: textTheme.bodySmall?.copyWith(color: teacherColor, fontSize: 11),
                                      maxLines: 4,
                                      softWrap: true,
                                    ),
                                  if (remark != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      remark,
                                      style: textTheme.bodySmall?.copyWith(fontSize: 11, color: infoColor),
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (!isActive) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      (weekDesc != null && weekDesc.isNotEmpty)
                                          ? '本周不上课 · $weekDesc'
                                          : '本周不上课',
                                      style: textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: Colors.black38,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showLessonDetail(
    BuildContext context,
    Lesson lesson,
    bool isActive,
    String? capturedSummary,
    String? aiSummary,
    bool isProcessing,
    ValueChanged<Lesson> onCaptureLesson,
    ValueChanged<Lesson> onRequestAiAnalysis,
    Map<String, List<ReviewTask>> reviewPlans,
    Set<String> planningLessons,
    ValueChanged<Lesson> onGenerateReviewPlan,
  ) {
    final hasCaptured = capturedSummary != null && capturedSummary.trim().isNotEmpty;
    final hasAiSummary = aiSummary != null && aiSummary.trim().isNotEmpty;
    final fallbackRemark = _formatLessonRemark(lesson.topic);
    final lessonKey = lessonStorageKey(lesson);
    final reviewTasks = reviewPlans[lessonKey] ?? const <ReviewTask>[];
    final isPlanningReview = planningLessons.contains(lessonKey);
    final canGenerateReviewPlan = hasAiSummary || hasCaptured;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        double clampHeight(double fraction, double min, double max) {
          final value = MediaQuery.of(ctx).size.height * fraction;
          return value.clamp(min, max).toDouble();
        }
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
            top: 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson.courseName,
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatTime(lesson.startTime)} - ${_formatTime(lesson.endTime)}  | ${lesson.location}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        if (!isActive)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '提示：课程安排在其他周，本周无需上课',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.orange),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (lesson.teacher.trim().isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18),
                    const SizedBox(width: 6),
                    Text('教师：${lesson.teacher}'),
                  ],
                ),
              const SizedBox(height: 12),
              if (hasAiSummary)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '课堂要点（AI 摘要）',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: clampHeight(0.4, 200, 420),
                      child: Markdown(
                        data: aiSummary!.trim(),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                )
              else if (hasCaptured)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('课堂要点', style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('原始课堂内容已抓取完毕，待 AI 分析后会在此展示摘要。'),
                    if (isProcessing)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: const [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('AI 分析进行中…'),
                          ],
                        ),
                      ),
                    if (!isProcessing)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            onRequestAiAnalysis(lesson);
                          },
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('立即触发 AI 提炼'),
                        ),
                      ),
                  ],
                )
              else if (fallbackRemark != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('课堂要点', style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: clampHeight(0.3, 160, 360),
                      child: SingleChildScrollView(
                        child: Text(
                          fallbackRemark,
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('暂无课堂要点', style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('尚未抓取该课程的详细内容，可立即前往教学网站抓取。'),
                  ],
                ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onCaptureLesson(lesson);
                    },
                    icon: Icon(hasCaptured ? Icons.add_circle_outline : Icons.play_arrow_rounded),
                    label: Text(hasCaptured ? '补充抓取 / 增加细节' : '去抓取'),
                  ),
                  if (hasCaptured) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onCaptureLesson(lesson);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新抓取'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('复习日程', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (reviewTasks.isEmpty)
                    Text(
                      canGenerateReviewPlan ? '尚未生成复习日程，点击下方按钮即可根据 AI 要点自动生成。' : '请先完成抓取或 AI 提炼，才能生成复习日程。',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.25,
                      ),
                      child: ListView.separated(
                        physics: const ClampingScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: reviewTasks.length,
                        separatorBuilder: (_, __) => const Divider(height: 8),
                        itemBuilder: (context, index) {
                          final task = reviewTasks[index];
                          final timeLabel =
                              '${task.scheduledAt.month}/${task.scheduledAt.day} ${_formatTime(task.scheduledAt)}';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.task_alt_outlined),
                            title: Text('${task.focus} (${task.method ?? '复习'})'),
                            subtitle: Text('$timeLabel · 建议${task.durationMinutes}分钟'),
                            dense: true,
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: !canGenerateReviewPlan || isPlanningReview
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            onGenerateReviewPlan(lesson);
                          },
                    icon: isPlanningReview
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(reviewTasks.isEmpty ? Icons.auto_fix_high : Icons.refresh),
                    label: Text(reviewTasks.isEmpty ? '生成复习日程' : '重新生成复习日程'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class AgendaTab extends StatefulWidget {
  const AgendaTab({
    super.key,
    required this.items,
    required this.currentDate,
    required this.onDateChange,
    required this.onDeleteAutoTask,
    required this.reminderSettings,
  });

  final List<ScheduleItem> items;
  final DateTime currentDate;
  final ValueChanged<DateTime> onDateChange;
  final ValueChanged<String> onDeleteAutoTask;
  final ReminderSettings reminderSettings;

  @override
  State<AgendaTab> createState() => AgendaTabState();
}

class AgendaTabState extends State<AgendaTab> {
  static const String _manualAgendaPrefKey = 'manual_agenda_items';

  late List<ScheduleItem> _items;
  int _transitionDirection = 0;
  final Map<String, List<ScheduleItem>> _manualItems = {};
  bool _shouldResetDirection = false;

  @override
  void initState() {
    super.initState();
    _items = _buildMergedItems(widget.currentDate, widget.items);
    _loadManualItems();
  }

  @override
  void didUpdateWidget(covariant AgendaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dateChanged = !_isSameDay(oldWidget.currentDate, widget.currentDate);
    if (dateChanged || !listEquals(oldWidget.items, widget.items)) {
      setState(() {
        _items = _buildMergedItems(widget.currentDate, widget.items);
      });
    }
    if (dateChanged) {
      _shouldResetDirection = true;
    }
    if (oldWidget.reminderSettings != widget.reminderSettings) {
      _syncManualReminders();
    }
  }

  List<ScheduleItem> _buildMergedItems(DateTime date, List<ScheduleItem> base) {
    final key = _dateKey(date);
    final merged = [...base];
    final manuals = _manualItems[key];
    if (manuals != null && manuals.isNotEmpty) {
      merged.addAll(manuals);
    }
    merged.sort((a, b) => a.time.compareTo(b.time));
    return merged;
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadManualItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_manualAgendaPrefKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = <String, List<ScheduleItem>>{};
      decoded.forEach((key, value) {
        if (value is List) {
          final list = value
              .map((e) => _manualItemFromJson(Map<String, dynamic>.from(e as Map)))
              .whereType<ScheduleItem>()
              .toList();
          if (list.isNotEmpty) {
            map[key.toString()] = list;
          }
        }
      });
      if (!mounted) return;
      setState(() {
        _manualItems
          ..clear()
          ..addAll(map);
        _items = _buildMergedItems(widget.currentDate, widget.items);
      });
      await _syncManualReminders();
    } catch (_) {
      // ignore malformed storage
    }
  }

  Future<void> _persistManualItems() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _manualItems.map(
      (key, value) => MapEntry(key, value.map(_manualItemToJson).toList()),
    );
    await prefs.setString(_manualAgendaPrefKey, jsonEncode(map));
    await _syncManualReminders();
  }

  ScheduleItem? _manualItemFromJson(Map<String, dynamic> json) {
    try {
      final millis = json['time'] as int;
      return ScheduleItem(
        title: json['title']?.toString() ?? '',
        detail: json['detail']?.toString() ?? '',
        time: DateTime.fromMillisecondsSinceEpoch(millis),
        isAuto: false,
        reviewTaskKey: null,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _manualItemToJson(ScheduleItem item) => {
        'title': item.title,
        'detail': item.detail,
        'time': item.time.millisecondsSinceEpoch,
      };

  void _addManualItemToMap(ScheduleItem item) {
    final key = _dateKey(item.time);
    final list = _manualItems.putIfAbsent(key, () => []);
    list.add(item);
  }

  void _removeManualItemFromMap(ScheduleItem item) {
    final key = _dateKey(item.time);
    final list = _manualItems[key];
    list?.removeWhere((element) => identical(element, item));
    if (list != null && list.isEmpty) {
      _manualItems.remove(key);
    }
  }

  Future<void> _syncManualReminders() async {
    await ReminderService.instance.syncManualItems(
      settings: widget.reminderSettings,
      items: _manualItems.values.expand((e) => e),
    );
  }

  void createSchedule(BuildContext context) {
    _openEditDialog(context);
  }

  Future<void> resyncManualReminders(ReminderSettings settings) async {
    await ReminderService.instance.syncManualItems(
      settings: settings,
      items: _manualItems.values.expand((e) => e),
    );
  }

  void _openEditDialog(BuildContext context, {ScheduleItem? origin, int? index}) async {
    final titleCtrl = TextEditingController(text: origin?.title ?? '');
    final detailCtrl = TextEditingController(text: origin?.detail ?? '');
    final now = DateTime.now();
    final defaultDate = DateTime(widget.currentDate.year, widget.currentDate.month, widget.currentDate.day, now.hour, now.minute);
    DateTime selected = origin?.time ?? defaultDate;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickDateTime() async {
              final date = await showDatePicker(
                context: dialogContext,
                initialDate: selected,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date == null) return;
              final time = await showTimePicker(
                context: dialogContext,
                initialTime: TimeOfDay.fromDateTime(selected),
              );
              if (time == null) return;
              setDialogState(() {
                selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
              });
            }

            return AlertDialog(
              title: Text(origin == null ? '添加日程' : '编辑日程'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '标题')),
                    TextField(controller: detailCtrl, decoration: const InputDecoration(labelText: '详情'), maxLines: 2),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')} '
                            '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                          ),
                        ),
                        TextButton(onPressed: pickDateTime, child: const Text('选择时间')),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
                ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('保存')),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    final newItem = ScheduleItem(
      title: titleCtrl.text.isEmpty ? '未命名日程' : titleCtrl.text,
      detail: detailCtrl.text,
      time: selected,
      isAuto: false,
      reviewTaskKey: null,
    );

    setState(() {
      if (index != null) {
        final oldItem = _items[index];
        if (!oldItem.isAuto) {
          _removeManualItemFromMap(oldItem);
        }
      }
      _addManualItemToMap(newItem);
      _items = _buildMergedItems(widget.currentDate, widget.items);
    });
    await _persistManualItems();
    final remindAt = ReminderService.instance.previewReminderTime(newItem.time, widget.reminderSettings);
    if (!mounted) return;
    if (remindAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒未安排（可能已过期或处于免打扰时段）')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('提醒已安排：${_formatTime(remindAt)}')),
    );
  }

  Future<void> _deleteItem(int index) async {
    final item = _items[index];
    if (item.isAuto) {
      setState(() {
        _items.removeAt(index);
      });
      return;
    }
    _removeManualItemFromMap(item);
    setState(() {
      _items = _buildMergedItems(widget.currentDate, widget.items);
    });
    await _persistManualItems();
  }

  void _handleHorizontalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 150) {
      _setDateWithDirection(widget.currentDate.subtract(const Duration(days: 1)), -1);
    } else if (velocity < -150) {
      _setDateWithDirection(widget.currentDate.add(const Duration(days: 1)), 1);
    }
  }

  void _setDateWithDirection(DateTime target, int direction) {
    setState(() {
      _transitionDirection = direction;
    });
    widget.onDateChange(target);
  }

  @override
  Widget build(BuildContext context) {
    final Widget listContent = _items.isEmpty
        ? const Center(child: Text('今日暂无待办，点击右下角可添加'))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemBuilder: (context, index) {
              final item = _items[index];
              final itemKey = ValueKey('${item.title}-${item.time.toIso8601String()}');
              return Dismissible(
                key: itemKey,
                background: Container(
                  color: Colors.red.withOpacity(0.8),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                secondaryBackground: Container(
                  color: Colors.red.withOpacity(0.8),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  if (item.isAuto && item.reviewTaskKey != null) {
                    widget.onDeleteAutoTask(item.reviewTaskKey!);
                  }
                  await _deleteItem(index);
                  return true;
                },
                child: _ScheduleItemCard(
                  item: item,
                  onEdit: item.isAuto ? null : () => _openEditDialog(context, origin: item, index: index),
                  onDelete: () {
                    _deleteItem(index);
                  },
                ),
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: _items.length,
          );

    final dateKey = _dateKey(widget.currentDate);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _DateSwitcher(
            date: widget.currentDate,
            onPrevious: () => _setDateWithDirection(widget.currentDate.subtract(const Duration(days: 1)), -1),
            onNext: () => _setDateWithDirection(widget.currentDate.add(const Duration(days: 1)), 1),
            onPick: () => _pickAgendaDate(context),
          ),
        ),
        Expanded(child: listContent),
      ],
    );

    final animatedBody = AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        final clamped = _transitionDirection.clamp(-1, 1).toDouble();
        final offsetTween = Tween<Offset>(
          begin: Offset(clamped * 0.8, 0),
          end: Offset.zero,
        );
        return SlideTransition(
          position: offsetTween.animate(curved),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(dateKey), child: column),
    );

    if (_shouldResetDirection && _transitionDirection != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _transitionDirection = 0;
          _shouldResetDirection = false;
        });
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _handleHorizontalSwipe,
      child: animatedBody,
    );
  }

  Future<void> _pickAgendaDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.currentDate,
      firstDate: DateTime(widget.currentDate.year - 1),
      lastDate: DateTime(widget.currentDate.year + 1),
    );
    if (picked != null) {
      if (_isSameDay(picked, widget.currentDate)) return;
      final direction = picked.isBefore(widget.currentDate) ? -1 : 1;
      _setDateWithDirection(picked, direction);
    }
  }
}

class UserTab extends StatelessWidget {
  const UserTab({
    super.key,
    required this.onOpenImport,
    required this.onPickTermStart,
    required this.themeSetting,
    required this.onThemeChanged,
    required this.reminderSettings,
    required this.onReminderChanged,
    this.termStartDate,
  });

  final VoidCallback onOpenImport;
  final VoidCallback onPickTermStart;
  final AppThemeSetting themeSetting;
  final ValueChanged<AppThemeSetting> onThemeChanged;
  final ReminderSettings reminderSettings;
  final ValueChanged<ReminderSettings> onReminderChanged;
  final DateTime? termStartDate;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final secondaryText = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70);
    final startLabel = termStartDate != null
        ? '当前开学日：${termStartDate!.year}-${termStartDate!.month.toString().padLeft(2, '0')}-${termStartDate!.day.toString().padLeft(2, '0')}'
        : '尚未设置本学期开学日期';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [color.primary, color.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: color.primary.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '导入课程表',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '在内置 WebView 登录教务系统，自动抓取并更新课堂信息，生成智能复习计划。',
                style: secondaryText,
              ),
              const SizedBox(height: 12),
              Text(
                startLabel,
                style: secondaryText,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: color.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: onOpenImport,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('打开教务网站并导入'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.7)),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: onPickTermStart,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('设置学期第一周第一天'),
              ),
              const SizedBox(height: 6),
              Text('支持 i.sjtu.edu.cn', style: secondaryText),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('提醒设置', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '当复习日程即将开始时提前发送提醒；在免打扰时段内不会推送通知。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用复习提醒'),
                  subtitle: const Text('在每个复习任务开始前自动提醒'),
                  value: reminderSettings.enableDailyReminder,
                  onChanged: (value) => onReminderChanged(reminderSettings.copyWith(enableDailyReminder: value)),
                ),
                const SizedBox(height: 8),
                Text('提前量', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [0, 1, 5, 10, 20, 30, 45, 60, 90, 120]
                      .map(
                        (minutes) => ChoiceChip(
                          label: Text('$minutes 分钟'),
                          selected: reminderSettings.leadMinutes == minutes,
                          onSelected: (_) => onReminderChanged(reminderSettings.copyWith(leadMinutes: minutes)),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('免打扰时段'),
                  subtitle: Text(
                      '在 ${_formatTimeOfDay(reminderSettings.quietStart)} - ${_formatTimeOfDay(reminderSettings.quietEnd)} 之间不推送提醒'),
                  value: reminderSettings.enableQuietHours,
                  onChanged: (value) => onReminderChanged(reminderSettings.copyWith(enableQuietHours: value)),
                ),
                ListTile(
                  dense: true,
                  enabled: reminderSettings.enableQuietHours,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('开始时间'),
                  trailing: Text(_formatTimeOfDay(reminderSettings.quietStart)),
                  onTap: reminderSettings.enableQuietHours
                      ? () => _pickTime(
                            context,
                            reminderSettings.quietStart,
                            (value) => onReminderChanged(reminderSettings.copyWith(quietStart: value)),
                          )
                      : null,
                ),
                ListTile(
                  dense: true,
                  enabled: reminderSettings.enableQuietHours,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('结束时间'),
                  trailing: Text(_formatTimeOfDay(reminderSettings.quietEnd)),
                  onTap: reminderSettings.enableQuietHours
                      ? () => _pickTime(
                            context,
                            reminderSettings.quietEnd,
                            (value) => onReminderChanged(reminderSettings.copyWith(quietEnd: value)),
                          )
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题风格', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('强调色', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: _themeColorOptions.map((option) {
                    final selected = themeSetting.seedColor.value == option.color.value;
                    return GestureDetector(
                      onTap: () => onThemeChanged(themeSetting.copyWith(seedColor: option.color)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: option.color,
                              border: Border.all(
                                color: selected ? option.color.withOpacity(0.8) : Colors.black12,
                                width: selected ? 4 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: option.color.withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            option.label,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: selected ? Theme.of(context).colorScheme.primary : null,
                                ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
}

  Future<void> _pickTime(BuildContext context, TimeOfDay initial, ValueChanged<TimeOfDay> onSelected) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) {
      onSelected(picked);
    }
  }
}

class _UserSettingTile extends StatelessWidget {
  const _UserSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ThemeColorOption {
  const _ThemeColorOption(this.label, this.color);
  final String label;
  final Color color;
}

const List<_ThemeColorOption> _themeColorOptions = [
  _ThemeColorOption('星辰蓝', Colors.indigo),
  _ThemeColorOption('薄荷绿', Color(0xFF2EC4B6)),
  _ThemeColorOption('晨曦橙', Color(0xFFFF9F1C)),
  _ThemeColorOption('暮霞粉', Color(0xFFE86AA7)),
];

class _ScheduleItemCard extends StatelessWidget {
  const _ScheduleItemCard({required this.item, this.onEdit, this.onDelete});

  final ScheduleItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final timeLabel = localizations.formatMediumDate(item.time);
    final hourLabel = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(item.time),
      alwaysUse24HourFormat: true,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: item.isAuto
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                    : Colors.amber.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.isAuto ? '自动生成' : '手动添加',
                style: TextStyle(
                  color: item.isAuto ? Theme.of(context).colorScheme.primary : Colors.amber.shade800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(item.detail, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text('$timeLabel  $hourLabel', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit?.call();
                } else if (value == 'delete') {
                  onDelete?.call();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _DateSwitcher extends StatelessWidget {
  const _DateSwitcher({
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final label =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${_weekdayLabel(date.weekday)}';
    return Row(
      children: [
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: OutlinedButton(
            onPressed: onPick,
            child: Text(label),
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class Lesson {
  Lesson({
    required this.courseName,
    required this.teacher,
    required this.startTime,
    required this.endTime,
    required this.topic,
    required this.location,
    this.weekPattern,
  });

  final String courseName;
  final String teacher;
  final DateTime startTime;
  final DateTime endTime;
  final String topic;
  final String location;
  final WeekPattern? weekPattern;

  Map<String, dynamic> toJson() => {
        'courseName': courseName,
        'teacher': teacher,
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
        'topic': topic,
        'location': location,
        'weekPattern': weekPattern?.toJson(),
      };

  static Lesson? fromJson(Map<String, dynamic> json) {
    try {
      return Lesson(
        courseName: json['courseName']?.toString() ?? '',
        teacher: json['teacher']?.toString() ?? '',
        startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int),
        endTime: DateTime.fromMillisecondsSinceEpoch(json['endTime'] as int),
        topic: json['topic']?.toString() ?? '',
        location: json['location']?.toString() ?? '',
        weekPattern: WeekPattern.fromJson(json['weekPattern']),
      );
    } catch (_) {
      return null;
    }
  }
}

class LessonAiException implements Exception {
  const LessonAiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LessonAiSummarizer {
  LessonAiSummarizer._();
  static final LessonAiSummarizer instance = LessonAiSummarizer._();
  static const String _endpoint = 'https://api.siliconflow.cn/v1/chat/completions';
  static const String _model = 'deepseek-ai/DeepSeek-V3.2';
  final http.Client _client = http.Client();

  Future<String> summarize(Lesson lesson, String rawContent) async {
    await AppSecrets.ensureLoaded();
    final apiKey = AppSecrets.siliconApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw const LessonAiException('未找到 SILICONFLOW_API_KEY，请在 .env 或环境变量中配置');
    }
    if (rawContent.trim().isEmpty) {
      throw const LessonAiException('原始课堂内容为空，无法进行分析');
    }
    final prep = await _prepareInputs(lesson, rawContent);
    final userContent = _buildMultimodalContent(lesson, prep);
    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': _model,
            'messages': [
              {
                'role': 'system',
                'content':
                    '你是一名大学学习助理，需要将课堂内容整理为易于复习的中文要点，语气专业且精炼，分条展示。',
              },
              {'role': 'user', 'content': userContent},
            ],
            'temperature': 0.2,
            'max_tokens': 2000,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode >= 400) {
      throw LessonAiException('硅基流动接口异常：${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const LessonAiException('AI 没有返回有效内容');
    }
    final message = choices.first['message'] as Map<String, dynamic>? ?? {};
    final content = message['content'] as String? ?? '';
    if (content.trim().isEmpty) {
      throw const LessonAiException('AI 返回内容为空');
    }
    return content.trim();
  }

  Future<_LessonAiInputs> _prepareInputs(Lesson lesson, String raw) async {
    final cleaned = raw.split('\n').map((e) => e.trimRight()).join('\n');
    final textBuffer = StringBuffer();
    bool inImageBlock = false;
    for (final line in cleaned.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('【PPT 图片】')) {
        inImageBlock = true;
        continue;
      }
      if (trimmed.startsWith('【') && trimmed.contains('】') && !trimmed.startsWith('【PPT 图片】')) {
        inImageBlock = false;
        continue;
      }
      if (inImageBlock) {
        continue;
      } else {
        textBuffer.writeln(line);
      }
    }
    return _LessonAiInputs(textBuffer.toString().trim(), const []);
  }

  List<Map<String, dynamic>> _buildMultimodalContent(
    Lesson lesson,
    _LessonAiInputs inputs,
  ) {
    final buffer = StringBuffer()
      ..writeln('课程：${lesson.courseName}')
      ..writeln('时间：${_formatTime(lesson.startTime)}-${_formatTime(lesson.endTime)}')
      ..writeln('地点：${lesson.location}')
      ..writeln('教师：${lesson.teacher}')
      ..writeln('\n课堂原始内容：\n${inputs.textContent}')
      ..writeln('\n请按照以下结构输出：\n1. 课堂概述（2-3 句）\n2. 核心知识点（条目）\n3. 难点与提醒（条目）\n4. 作业或复习建议（条目）');
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': buffer.toString()},
    ];
    return content;
  }

}

class _LessonAiInputs {
  _LessonAiInputs(this.textContent, this.images);
  final String textContent;
  final List<String> images;
}

class ReviewPlanSuggestion {
  const ReviewPlanSuggestion({
    required this.topic,
    required this.method,
    required this.durationMinutes,
    this.tip,
  });

  final String topic;
  final String method;
  final int durationMinutes;
  final String? tip;

  static ReviewPlanSuggestion? fromJson(Map<String, dynamic> json) {
    try {
      final topic = json['topic']?.toString() ?? '';
      final method = json['method']?.toString() ?? '';
      if (topic.trim().isEmpty || method.trim().isEmpty) return null;
      final duration = json['durationMinutes'] as int? ?? 30;
      final tip = json['tip']?.toString();
      return ReviewPlanSuggestion(
        topic: topic.trim(),
        method: method.trim(),
        durationMinutes: duration <= 0 ? 30 : duration,
        tip: tip?.trim().isEmpty ?? true ? null : tip?.trim(),
      );
    } catch (_) {
      return null;
    }
  }
}

class LessonReviewPlanGenerator {
  LessonReviewPlanGenerator._();
  static final LessonReviewPlanGenerator instance = LessonReviewPlanGenerator._();
  final http.Client _client = http.Client();

  Future<List<ReviewPlanSuggestion>> generate(Lesson lesson, String summary) async {
    await AppSecrets.ensureLoaded();
    final apiKey = AppSecrets.siliconApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw const LessonAiException('未找到 SILICONFLOW_API_KEY，请在 .env 或环境变量中配置');
    }
    final buffer = StringBuffer()
      ..writeln('课程：${lesson.courseName}')
      ..writeln('教师：${lesson.teacher}')
      ..writeln('时间：${_formatTime(lesson.startTime)}-${_formatTime(lesson.endTime)}')
      ..writeln('地点：${lesson.location}')
      ..writeln('课堂要点：\n$summary')
      ..writeln('\n请基于以上内容给出 3-5 条复习任务建议，每条包含：topic(复习重点)、method(复习方式)、durationMinutes(建议用时，整数分钟)、tip(可选补充)。')
      ..writeln('请严格输出 JSON 数组，如 [{"topic":"...","method":"...","durationMinutes":30,"tip":"..."}]，不得包含额外文字。');

    final response = await _client
        .post(
          Uri.parse(LessonAiSummarizer._endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': LessonAiSummarizer._model,
            'messages': [
              {
                'role': 'system',
                'content': '你是学习规划助理，负责根据课堂要点生成结构化复习任务。输出必须是 JSON 数组。',
              },
              {'role': 'user', 'content': buffer.toString()},
            ],
            'temperature': 0.2,
            'max_tokens': 800,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode >= 400) {
      throw LessonAiException('硅基流动接口异常：${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    Map<String, dynamic>? message;
    if (choices != null && choices.isNotEmpty) {
      message = choices.first['message'] as Map<String, dynamic>?;
    }
    final content = message?['content']?.toString().trim() ?? '';
    if (content.isEmpty) {
      throw const LessonAiException('AI 没有返回复习任务');
    }
    final jsonText = _extractJsonArray(content);
    final suggestionsRaw = jsonDecode(jsonText);
    if (suggestionsRaw is! List) {
      throw const LessonAiException('复习任务解析失败（非数组）');
    }
    final suggestions = suggestionsRaw
        .map((e) => ReviewPlanSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
        .whereType<ReviewPlanSuggestion>()
        .toList();
    if (suggestions.isEmpty) {
      throw const LessonAiException('复习任务解析失败（为空）');
    }
    return suggestions;
  }

  String _extractJsonArray(String content) {
    final start = content.indexOf('[');
    final end = content.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      return content.substring(start, end + 1);
    }
    return content;
  }
}

class AppSecrets {
  static bool _loaded = false;
  static String? _siliconKey;

  static String? get siliconApiKey => _siliconKey;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final envKey = Platform.environment['SILICONFLOW_API_KEY'];
    if (_assign(envKey)) return;
    final defined = const String.fromEnvironment('SILICONFLOW_API_KEY');
    if (_assign(defined)) return;
    final fileKey = await _readFromFile();
    if (_assign(fileKey)) return;
    final assetKey = await _readFromAsset();
    _assign(assetKey);
  }

  static bool _assign(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    _siliconKey = trimmed;
    return true;
  }

  static Future<String?> _readFromFile() async {
    try {
      final file = File('.env');
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return _extractKey(content);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readFromAsset() async {
    try {
      final content = await rootBundle.loadString('.env');
      return _extractKey(content);
    } catch (_) {
      return null;
    }
  }

  static String? _extractKey(String content) {
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#') || trimmed.isEmpty) continue;
      final parts = trimmed.split('=');
      if (parts.length < 2) continue;
      final key = parts.first.trim();
      if (key == 'SILICONFLOW_API_KEY') {
        return parts.sublist(1).join('=').trim();
      }
    }
    return null;
  }
}

String lessonStorageKey(Lesson lesson) {
  final start = lesson.startTime.toIso8601String();
  final name = lesson.courseName.trim();
  final location = lesson.location.trim();
  final teacher = lesson.teacher.trim();
  return '$name|$location|$teacher|$start';
}

class ReviewTask {
  ReviewTask({
    required this.courseName,
    required this.scheduledAt,
    required this.offsetFromLesson,
    required this.focus,
    this.note,
    this.method,
    this.durationMinutes = 30,
    this.lessonKey = '',
    this.aiAdvice,
  });

  final String courseName;
  final DateTime scheduledAt;
  final Duration offsetFromLesson;
  final String focus;
  final String? note;
  final String? method;
  final int durationMinutes;
  final String lessonKey;
  final String? aiAdvice;

  String get memoryCurveLabel {
    final hours = offsetFromLesson.inHours;
    if (hours < 24) return '课后${hours}小时';
    return '课后${offsetFromLesson.inDays}天';
  }

  Map<String, dynamic> toJson() => {
        'courseName': courseName,
        'scheduledAt': scheduledAt.millisecondsSinceEpoch,
        'offsetMinutes': offsetFromLesson.inMinutes,
        'focus': focus,
        'note': note,
        'method': method,
        'durationMinutes': durationMinutes,
        'lessonKey': lessonKey,
        'aiAdvice': aiAdvice,
      };

  static ReviewTask? fromJson(Map<String, dynamic> json) {
    try {
      final scheduledAt = DateTime.fromMillisecondsSinceEpoch(json['scheduledAt'] as int);
      final offsetMinutes = json['offsetMinutes'] as int? ?? 0;
      return ReviewTask(
        courseName: json['courseName']?.toString() ?? '',
        scheduledAt: scheduledAt,
        offsetFromLesson: Duration(minutes: offsetMinutes),
        focus: json['focus']?.toString() ?? '',
        note: json['note']?.toString(),
        method: json['method']?.toString(),
        durationMinutes: json['durationMinutes'] as int? ?? 30,
        lessonKey: json['lessonKey']?.toString() ?? '',
        aiAdvice: json['aiAdvice']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

String reviewTaskStorageKey(ReviewTask task) {
  return '${task.lessonKey}|${task.scheduledAt.millisecondsSinceEpoch}';
}

class WeekPattern {
  const WeekPattern({this.startWeek, this.endWeek, this.parity = WeekParity.any});

  final int? startWeek;
  final int? endWeek;
  final WeekParity parity;

  bool isActive(int currentWeek) {
    if (currentWeek <= 0) return false;
    if (startWeek != null && currentWeek < startWeek!) return false;
    if (endWeek != null && currentWeek > endWeek!) return false;
    if (parity == WeekParity.odd && currentWeek % 2 == 0) return false;
    if (parity == WeekParity.even && currentWeek % 2 != 0) return false;
    return true;
  }

  String description() {
    final range = startWeek != null
        ? endWeek != null && endWeek != startWeek
            ? '$startWeek-$endWeek周'
            : '$startWeek周'
        : '';
    final parityLabel = parity == WeekParity.odd
        ? '仅单周'
        : parity == WeekParity.even
            ? '仅双周'
            : '';
    return [range, parityLabel].where((e) => e.isNotEmpty).join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'startWeek': startWeek,
        'endWeek': endWeek,
        'parity': parity.name,
      };

  static WeekPattern? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    final parityName = map['parity']?.toString();
    WeekParity parity = WeekParity.any;
    if (parityName != null) {
      parity = WeekParity.values.firstWhere(
        (p) => p.name == parityName,
        orElse: () => WeekParity.any,
      );
    }
    return WeekPattern(
      startWeek: map['startWeek'] as int?,
      endWeek: map['endWeek'] as int?,
      parity: parity,
    );
  }
}

enum WeekParity { any, odd, even }

class ScheduleItem {
  ScheduleItem({
    required this.title,
    required this.detail,
    required this.time,
    this.isAuto = true,
    this.reviewTaskKey,
  });

  final String title;
  final String detail;
  final DateTime time;
  final bool isAuto;
  final String? reviewTaskKey;
}

class WeekDayLessons {
  WeekDayLessons({required this.date, required this.lessons});

  final DateTime date;
  final List<Lesson> lessons;
}

class WeeklyScheduleOverview {
  WeeklyScheduleOverview({
    required this.weekDays,
    required this.scheduleItems,
  });

  final List<WeekDayLessons> weekDays;
  final List<ScheduleItem> scheduleItems;
}

typedef ReviewTaskProvider = List<ReviewTask> Function(DateTime day);

class ScheduleService {
  ScheduleService({
    ScheduleRepository? repository,
    ReviewPlanner? planner,
    this.reviewTaskProvider,
    this.enableAutoReviewPlan = true,
  })  : _repository = repository ?? MockScheduleRepository(),
        _planner = planner ?? ReviewPlanner();

  final ScheduleRepository _repository;
  final ReviewPlanner _planner;
  final ReviewTaskProvider? reviewTaskProvider;
  final bool enableAutoReviewPlan;

  Future<WeeklyScheduleOverview> loadWeekOverview(DateTime anchorDay) async {
    final monday = anchorDay.subtract(Duration(days: anchorDay.weekday - 1));
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));

    final List<WeekDayLessons> results = [];
    final List<ReviewTask> allReviewTasks = [];

    for (final day in weekDays) {
      final lessons = await _repository.fetchLessonsForDate(day);
      results.add(WeekDayLessons(date: day, lessons: lessons));
      if (enableAutoReviewPlan) {
        allReviewTasks.addAll(_planner.generatePlan(lessons));
      }
    }

    final scheduleItems = _buildScheduleItems(allReviewTasks, anchorDay);
    return WeeklyScheduleOverview(weekDays: results, scheduleItems: scheduleItems);
  }

  List<ScheduleItem> _buildScheduleItems(List<ReviewTask> tasks, DateTime anchorDay) {
    final todayStart = DateTime(anchorDay.year, anchorDay.month, anchorDay.day);
    final combined = <ReviewTask>[];
    combined.addAll(tasks);
    if (reviewTaskProvider != null) {
      combined.addAll(reviewTaskProvider!(todayStart));
    }
    final todayItems = combined
        .where((t) => _isSameDay(t.scheduledAt, todayStart))
        .map(
          (t) => ScheduleItem(
            title: '${t.courseName} · 复习',
            detail: [
              t.memoryCurveLabel,
              if (t.focus.trim().isNotEmpty) '重点：${t.focus}',
              if ((t.method ?? t.note)?.trim().isNotEmpty ?? false) '方式：${(t.method ?? t.note)!.trim()}',
            ].join(' | '),
            time: t.scheduledAt,
            isAuto: true,
            reviewTaskKey: reviewTaskStorageKey(t),
          ),
        )
        .toList();

    todayItems.sort((a, b) => a.time.compareTo(b.time));
    return todayItems;
  }
}

abstract class ScheduleRepository {
  Future<List<Lesson>> fetchLessonsForDate(DateTime date);
}

class MockScheduleRepository implements ScheduleRepository {
  @override
  Future<List<Lesson>> fetchLessonsForDate(DateTime date) async {
    await Future<void>.delayed(const Duration(milliseconds: 240));
    final dayStart = DateTime(date.year, date.month, date.day);

    if (date.weekday == DateTime.tuesday) {
      return [
        Lesson(
          courseName: '职业规划',
          teacher: '周老师',
          startTime: dayStart.add(const Duration(hours: 10)),
          endTime: dayStart.add(const Duration(hours: 11, minutes: 30)),
          topic: '简历与面试技巧',
          location: '学生中心201',
          weekPattern: const WeekPattern(),
        ),
      ];
    }

    if (date.weekday == DateTime.thursday) {
      return [
        Lesson(
          courseName: '心理健康',
          teacher: '黄老师',
          startTime: dayStart.add(const Duration(hours: 15)),
          endTime: dayStart.add(const Duration(hours: 16, minutes: 30)),
          topic: '压力管理与自我调节',
          location: '教学楼C区102',
          weekPattern: const WeekPattern(),
        ),
      ];
    }

    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return [];
    }

    return [
      Lesson(
        courseName: '高等数学',
        teacher: '王老师',
        startTime: dayStart.add(const Duration(hours: 8)),
        endTime: dayStart.add(const Duration(hours: 9, minutes: 40)),
        topic: '第5章 定积分与应用',
        location: '教学楼A区205',
        weekPattern: const WeekPattern(),
      ),
      Lesson(
        courseName: '大学英语',
        teacher: '李老师',
        startTime: dayStart.add(const Duration(hours: 10, minutes: 10)),
        endTime: dayStart.add(const Duration(hours: 11, minutes: 40)),
        topic: 'Unit 6 Reading Skills',
        location: '教学楼B区308',
        weekPattern: const WeekPattern(),
      ),
      Lesson(
        courseName: '数据结构',
        teacher: '陈老师',
        startTime: dayStart.add(const Duration(hours: 14)),
        endTime: dayStart.add(const Duration(hours: 15, minutes: 40)),
        topic: '第3章 栈与队列',
        location: '信息楼C区101',
        weekPattern: const WeekPattern(),
      ),
    ];
  }
}

class MemoryScheduleRepository implements ScheduleRepository {
  MemoryScheduleRepository({required List<Lesson> lessons})
      : _lessons = List.of(lessons);

  final List<Lesson> _lessons;

  @override
  Future<List<Lesson>> fetchLessonsForDate(DateTime date) async {
    final target = DateTime(date.year, date.month, date.day);
    return _lessons
        .where((lesson) => _isSameDay(lesson.startTime, target))
        .toList();
  }
}

const List<Duration> kReviewPlanIntervals = [
  Duration(hours: 4),
  Duration(days: 1),
  Duration(days: 3),
  Duration(days: 7),
  Duration(days: 14),
];

class ReviewPlanner {
  ReviewPlanner({List<Duration>? reviewIntervals})
      : reviewIntervals = reviewIntervals ??
            const [
              Duration(hours: 4),
              Duration(days: 1),
              Duration(days: 3),
              Duration(days: 7),
            ];

  final List<Duration> reviewIntervals;

  List<ReviewTask> generatePlan(List<Lesson> lessons) {
    final tasks = <ReviewTask>[];
    for (final lesson in lessons) {
      for (final interval in reviewIntervals) {
        final scheduledTime = lesson.endTime.add(interval);
        tasks.add(
          ReviewTask(
            courseName: lesson.courseName,
            scheduledAt: scheduledTime,
            offsetFromLesson: interval,
            focus: lesson.topic,
            note: _buildSuggestion(interval),
            lessonKey: lessonStorageKey(lesson),
          ),
        );
      }
    }
    tasks.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return tasks;
  }

  String? _buildSuggestion(Duration interval) {
    if (interval.inHours <= 6) return '快速回顾课堂笔记，标记不确定点。';
    if (interval.inDays <= 1) return '完成配套习题，检查理解的准确性。';
    if (interval.inDays <= 3) return '整理错题与难点，尝试讲解给同伴听。';
    if (interval.inDays <= 7) return '结合记忆曲线回顾核心知识，准备下阶段学习。';
    return null;
  }
}

class LessonSpan {
  LessonSpan({required this.startIndex, required this.slotCount});
  final int startIndex;
  final int slotCount;
}

LessonSpan? _lessonSpan(Lesson lesson, DateTime day) {
  int? startIdx;
  int? endIdx;
  for (var i = 0; i < kTimeSlots.length; i++) {
    final slot = kTimeSlots[i];
    final slotStart = DateTime(day.year, day.month, day.day, slot.start.hour, slot.start.minute);
    final slotEnd = DateTime(day.year, day.month, day.day, slot.end.hour, slot.end.minute);
    final overlap = lesson.startTime.isBefore(slotEnd) && lesson.endTime.isAfter(slotStart);
    if (overlap) {
      startIdx ??= i + 1;
      endIdx = i + 1;
    }
  }
  if (startIdx == null || endIdx == null) return null;
  return LessonSpan(startIndex: startIdx, slotCount: endIdx - startIdx + 1);
}

class TimeSlot {
  const TimeSlot({
    required this.index,
    required this.label,
    required this.timeRange,
    required this.start,
    required this.end,
  });

  final int index;
  final String label;
  final String timeRange;
  final TimeOfDay start;
  final TimeOfDay end;
}

const List<TimeSlot> kTimeSlots = [
  TimeSlot(index: 1, label: '第1节', timeRange: '08:00-08:45', start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 8, minute: 45)),
  TimeSlot(index: 2, label: '第2节', timeRange: '08:55-09:40', start: TimeOfDay(hour: 8, minute: 55), end: TimeOfDay(hour: 9, minute: 40)),
  TimeSlot(index: 3, label: '第3节', timeRange: '10:00-10:45', start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 10, minute: 45)),
  TimeSlot(index: 4, label: '第4节', timeRange: '10:55-11:40', start: TimeOfDay(hour: 10, minute: 55), end: TimeOfDay(hour: 11, minute: 40)),
  TimeSlot(index: 5, label: '第5节', timeRange: '12:00-12:45', start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 12, minute: 45)),
  TimeSlot(index: 6, label: '第6节', timeRange: '12:55-13:40', start: TimeOfDay(hour: 12, minute: 55), end: TimeOfDay(hour: 13, minute: 40)),
  TimeSlot(index: 7, label: '第7节', timeRange: '14:00-14:45', start: TimeOfDay(hour: 14, minute: 0), end: TimeOfDay(hour: 14, minute: 45)),
  TimeSlot(index: 8, label: '第8节', timeRange: '14:55-15:40', start: TimeOfDay(hour: 14, minute: 55), end: TimeOfDay(hour: 15, minute: 40)),
  TimeSlot(index: 9, label: '第9节', timeRange: '16:00-16:45', start: TimeOfDay(hour: 16, minute: 0), end: TimeOfDay(hour: 16, minute: 45)),
  TimeSlot(index: 10, label: '第10节', timeRange: '16:55-17:40', start: TimeOfDay(hour: 16, minute: 55), end: TimeOfDay(hour: 17, minute: 40)),
  TimeSlot(index: 11, label: '第11节', timeRange: '18:00-18:45', start: TimeOfDay(hour: 18, minute: 0), end: TimeOfDay(hour: 18, minute: 45)),
  TimeSlot(index: 12, label: '第12节', timeRange: '18:55-19:40', start: TimeOfDay(hour: 18, minute: 55), end: TimeOfDay(hour: 19, minute: 40)),
  TimeSlot(index: 13, label: '第13节', timeRange: '19:40-20:20', start: TimeOfDay(hour: 19, minute: 40), end: TimeOfDay(hour: 20, minute: 20)),
];

class _DailyRestBlock {
  const _DailyRestBlock(this.start, this.end);
  final TimeOfDay start;
  final TimeOfDay end;

  DateTime startOn(DateTime day) => DateTime(day.year, day.month, day.day, start.hour, start.minute);
  DateTime endOn(DateTime day) => DateTime(day.year, day.month, day.day, end.hour, end.minute);
}

const List<_DailyRestBlock> kDailyRestBlocks = [
  _DailyRestBlock(TimeOfDay(hour: 11, minute: 40), TimeOfDay(hour: 13, minute: 20)),
];

const Duration kScheduleBuffer = Duration(minutes: 15);

String _weekdayLabel(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return '周一';
    case DateTime.tuesday:
      return '周二';
    case DateTime.wednesday:
      return '周三';
    case DateTime.thursday:
      return '周四';
    case DateTime.friday:
      return '周五';
    case DateTime.saturday:
      return '周六';
    case DateTime.sunday:
      return '周日';
    default:
      return '周';
  }
}

Color _courseColor(String courseName) {
  const palette = [
    Color(0xFF6C63FF),
    Color(0xFF2EC4B6),
    Color(0xFFFF9F1C),
    Color(0xFF6A4C93),
    Color(0xFF00B4D8),
    Color(0xFF2D6A4F),
    Color(0xFFEE6352),
    Color(0xFF3A86FF),
  ];
  final index = courseName.hashCode.abs() % palette.length;
  return palette[index];
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _timeOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
  return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
}

_DateTimeRange? _findRestOverlap(DateTime start, DateTime end) {
  for (final block in kDailyRestBlocks) {
    final windowStart = block.startOn(start);
    final windowEnd = block.endOn(start);
    if (_timeOverlap(windowStart, windowEnd, start, end)) {
      return _DateTimeRange(windowStart, windowEnd);
    }
  }
  return null;
}

class _DateTimeRange {
  const _DateTimeRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

String _formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.title,
    required this.scheduledAt,
  });

  final int id;
  final String title;
  final DateTime scheduledAt;
}

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();
  static const MethodChannel _alarmChannel = MethodChannel('alarm_scheduler');
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  final Set<int> _reviewIds = {};
  final Set<int> _manualIds = {};
  final Map<int, ScheduledReminder> _scheduled = {};

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(settings);
    if (Platform.isAndroid) {
      final androidSpecific = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidSpecific?.requestNotificationsPermission();
      await androidSpecific?.requestExactAlarmsPermission();
    } else if (Platform.isIOS) {
      final iosSpecific = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await iosSpecific?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      final macSpecific = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      await macSpecific?.requestPermissions(alert: true, badge: true, sound: true);
    }
    _initialized = true;
  }

  Future<void> syncReviewTasks({
    required ReminderSettings settings,
    required Iterable<ReviewTask> tasks,
  }) async {
    await ensureInitialized();
    await _cancelIds(_reviewIds);
    if (!settings.enableDailyReminder) return;
    for (final task in tasks) {
      final remindAt = _calculateReminderTime(task.scheduledAt, settings);
      if (remindAt == null) continue;
      final id = _notificationIdFromKey('review|${reviewTaskStorageKey(task)}');
      final body = [
        '${_formatTime(task.scheduledAt)}开始',
        if (task.focus.trim().isNotEmpty) '重点：${task.focus}',
        if ((task.method ?? '').trim().isNotEmpty) '方式：${task.method!.trim()}',
      ].join(' | ');
      await _scheduleAlarm(
        id: id,
        title: '${task.courseName} · 复习提醒',
        body: body,
        remindAt: remindAt,
      );
      _reviewIds.add(id);
    }
  }

  Future<void> syncManualItems({
    required ReminderSettings settings,
    required Iterable<ScheduleItem> items,
  }) async {
    await ensureInitialized();
    await _cancelIds(_manualIds);
    if (!settings.enableDailyReminder) return;
    for (final item in items) {
      final remindAt = _calculateReminderTime(item.time, settings);
      if (remindAt == null) continue;
      final id = _notificationIdFromKey('manual|${item.title}|${item.time.millisecondsSinceEpoch}');
      await _scheduleAlarm(
        id: id,
        title: item.title,
        body: item.detail.isEmpty ? '即将开始' : item.detail,
        remindAt: remindAt,
      );
      _manualIds.add(id);
    }
  }

  Future<void> showTestNotification() async {
    await ensureInitialized();
    await _plugin.show(
      _notificationIdFromKey('debug_test'),
      '测试提醒',
      '如果看到这条通知，说明提醒权限正常',
      _defaultNotificationDetails(),
    );
  }

  Future<void> scheduleQuickTestNotification() async {
    await ensureInitialized();
    final now = DateTime.now();
    final remindAt = now.add(const Duration(minutes: 1));
    await _scheduleAlarm(
      id: _notificationIdFromKey('debug_scheduled'),
      title: '测试排程提醒',
      body: '1 分钟后的排程提醒',
      remindAt: remindAt,
    );
  }

  List<ScheduledReminder> pendingRequests() {
    final list = _scheduled.values.toList();
    list.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return list;
  }

  DateTime? previewReminderTime(DateTime eventTime, ReminderSettings settings) {
    return _calculateReminderTime(eventTime, settings);
  }

  Future<void> _cancelIds(Set<int> ids) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      if (Platform.isAndroid) {
        await _alarmChannel.invokeMethod<void>('cancel', {'id': id});
      } else {
        await _plugin.cancel(id);
      }
      _scheduled.remove(id);
    }
    ids.clear();
  }

  DateTime? _calculateReminderTime(DateTime eventTime, ReminderSettings settings) {
    final now = DateTime.now();
    if (eventTime.isBefore(now)) {
      return null;
    }
    var remindAt = eventTime.subtract(Duration(minutes: settings.leadMinutes));
    if (remindAt.isBefore(now)) {
      remindAt = now.add(const Duration(seconds: 1));
    }
    if (_isInQuietHours(remindAt, settings)) {
      return null;
    }
    return remindAt;
  }

  bool _isInQuietHours(DateTime dateTime, ReminderSettings settings) {
    if (!settings.enableQuietHours) return false;
    final start = _timeOfDayToMinutes(settings.quietStart);
    final end = _timeOfDayToMinutes(settings.quietEnd);
    final current = dateTime.hour * 60 + dateTime.minute;
    if (start == end) return false;
    if (start < end) {
      return current >= start && current < end;
    }
    return current >= start || current < end;
  }

  NotificationDetails _defaultNotificationDetails() {
    final androidDetails = AndroidNotificationDetails(
      'review_schedule_v2',
      '复习日程提醒',
      channelDescription: '复习计划及自定义日程提醒',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    const iosDetails = DarwinNotificationDetails(presentAlert: true, presentSound: true);
    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  int _notificationIdFromKey(String key) {
    return key.hashCode & 0x7fffffff;
  }

  Future<void> _scheduleAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime remindAt,
  }) async {
    if (Platform.isAndroid) {
      await _alarmChannel.invokeMethod<void>('schedule', {
        'id': id,
        'title': title,
        'body': body,
        'triggerAtMillis': remindAt.millisecondsSinceEpoch,
      });
    } else {
      await _plugin.show(
        id,
        title,
        body,
        _defaultNotificationDetails(),
      );
    }
    _scheduled[id] = ScheduledReminder(id: id, title: title, scheduledAt: remindAt);
  }
}

String? _formatLessonRemark(String remark) {
  final clean = remark.trim();
  if (clean.isEmpty) return null;
  const keywords = ['主修', '必修', '选修', '通识', '课程标记'];
  final hasKeyword = keywords.any(clean.contains);
  final label = hasKeyword ? '课程标记' : '要点';
  return '$label：$clean';
}

class WebImportPage extends StatefulWidget {
  const WebImportPage({
    super.key,
    required this.onImported,
    this.termStartDate,
  });

  final ValueChanged<List<Lesson>> onImported;
  final DateTime? termStartDate;

  @override
  State<WebImportPage> createState() => _WebImportPageState();
}

class _WebImportPageState extends State<WebImportPage> {
  static const int _defaultWeekCount = 20;
  static const int _maxWeekCount = 30;

  late final WebViewController _controller;
  double _progress = 0;
  bool _isExtracting = false;
  List<Map<String, dynamic>> _scrapedCourses = [];
  String? _lastError;
  List<Lesson> _parsedLessons = [];

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) => setState(() => _progress = value / 100),
        ),
      )
      ..loadRequest(Uri.parse('https://i.sjtu.edu.cn'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教务系统'),
        actions: [
          IconButton(
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress < 1
              ? LinearProgressIndicator(value: _progress)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          _buildResultPanel(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isExtracting ? null : _extractCourses,
        icon: _isExtracting ? const CircularProgressIndicator() : const Icon(Icons.download),
        label: Text(_isExtracting ? '抓取中...' : '提取课程'),
      ),
    );
  }

  Widget _buildResultPanel() {
    if (_lastError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: Colors.red.withOpacity(0.1),
        child: Text('抓取失败：$_lastError'),
      );
    }
    if (_scrapedCourses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: Colors.grey.shade200,
        child: const Text('提示：登录后打开课表页面，点击“提取课程”即可抓取。'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 200,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _scrapedCourses.length,
            itemBuilder: (context, index) {
              final course = _scrapedCourses[index];
              final info = course['info'] as Map<String, dynamic>? ?? {};
              return Card(
                child: ListTile(
                  title: Text(course['title'] ?? '课程'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: info.entries.map((e) => Text('${e.key}：${e.value}')).toList(),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton.icon(
            onPressed: _parsedLessons.isEmpty ? null : _importToApp,
            icon: const Icon(Icons.check_circle_outline),
            label: Text('导入到课表（${_parsedLessons.length}条）'),
          ),
        ),
      ],
    );
  }

  Future<void> _extractCourses() async {
    const script = r'''
      (function() {
        const cells = Array.from(document.querySelectorAll('.timetable_con'));
        const rows = cells.map(cell => {
          const title = (cell.querySelector('.title')?.innerText || '').replace(/\s+/g, ' ').trim();
          const info = {};
          cell.querySelectorAll('p').forEach(p => {
            const label = (p.querySelector('[data-toggle="tooltip"]')?.getAttribute('title') || '').trim();
            const value = p.innerText.replace(/\s+/g, ' ').trim();
            if (label && value) {
              if (!info[label]) {
                info[label] = [];
              }
              info[label].push(value);
            }
          });
          const td = cell.closest('td');
          const rowSpan = td?.getAttribute('rowspan') || '';
          const colSpan = td?.getAttribute('colspan') || '';
          const id = td?.getAttribute('id') || '';
          let columnIndex = null;
          if (td) {
            const row = td.closest('tr');
            if (row) {
              const wrapCells = Array.from(row.querySelectorAll('td.td_wrap'));
              columnIndex = wrapCells.indexOf(td);
            }
          }
          return {
            title,
            rowSpan,
            colSpan,
            id,
            columnIndex,
            info,
          };
        });
        return JSON.stringify(rows);
      })();
    ''';

    setState(() {
      _isExtracting = true;
      _lastError = null;
    });

    try {
      final rawResult = await _controller.runJavaScriptReturningResult(script);
      final raw = rawResult.toString().trim();
      final normalized = raw.startsWith('"') && raw.endsWith('"')
          ? jsonDecode(raw) as String
          : raw;
      final decoded = jsonDecode(normalized) as List<dynamic>;
      setState(() {
        _scrapedCourses =
            decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _parsedLessons = _convertToLessons(_scrapedCourses);
      });
    } catch (e) {
      setState(() {
        _lastError = e.toString();
        _scrapedCourses = [];
        _parsedLessons = [];
      });
    } finally {
      setState(() {
        _isExtracting = false;
      });
    }
  }

  void _importToApp() {
    if (_parsedLessons.isEmpty) return;
    widget.onImported(_parsedLessons);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  List<Lesson> _convertToLessons(List<Map<String, dynamic>> rawCourses) {
    final templates = <_LessonTemplate>[];
    for (final course in rawCourses) {
      final template = _mapCourseToTemplate(course);
      if (template != null) {
        templates.add(template);
      }
    }
    return _expandTemplates(templates);
  }

  List<Lesson> _expandTemplates(List<_LessonTemplate> templates) {
    if (templates.isEmpty) return [];
    if (widget.termStartDate == null) {
      final monday = _currentWeekMonday();
      return templates
          .map(
            (tpl) => tpl.buildForDate(monday.add(Duration(days: tpl.dayOffset))),
          )
          .toList();
    }
    final normalizedStart = DateTime(
      widget.termStartDate!.year,
      widget.termStartDate!.month,
      widget.termStartDate!.day,
    );
    final lessons = <Lesson>[];
    for (final template in templates) {
      final pattern = template.weekPattern;
      int startWeek = pattern?.startWeek ?? 1;
      if (startWeek < 1) startWeek = 1;
      if (startWeek > _maxWeekCount) startWeek = _maxWeekCount;
      int endWeek = pattern?.endWeek ?? _defaultWeekCount;
      if (endWeek < startWeek) {
        endWeek = startWeek;
      }
      if (endWeek > _maxWeekCount) {
        endWeek = _maxWeekCount;
      }
      final fallbackEnd = startWeek > _defaultWeekCount ? startWeek : _defaultWeekCount;
      if (pattern?.endWeek == null && endWeek < fallbackEnd) {
        endWeek = fallbackEnd;
      }
      for (var week = startWeek; week <= endWeek; week++) {
        if (pattern != null && !pattern.isActive(week)) continue;
        final date = normalizedStart.add(Duration(days: (week - 1) * 7 + template.dayOffset));
        lessons.add(template.buildForDate(date));
      }
    }
    lessons.sort((a, b) => a.startTime.compareTo(b.startTime));
    return lessons;
  }

  _LessonTemplate? _mapCourseToTemplate(Map<String, dynamic> course) {
    final info = Map<String, dynamic>.from(course['info'] as Map? ?? {});
    final rowSpan = int.tryParse('${course['rowSpan'] ?? ''}');
    final slotText = _firstText(info['节/周']) ?? _firstText(info['节次']);
    final slotRange = _parseSlotRange(slotText, rowSpan: rowSpan);
    final dayOffset = _parseDayOffset(course['columnIndex'], course['id'] as String?);
    if (slotRange == null || dayOffset == null) return null;
    final startSlot = _slotByIndex(slotRange.start);
    final endSlot = _slotByIndex(slotRange.end);
    if (startSlot == null || endSlot == null) return null;

    final teachers = _normalizeList(info['教师']);
    final teacherLabel = teachers.isEmpty ? '' : teachers.join(' / ');

    final topics = _normalizeList(info['课程标记'] ?? info['选课备注']);
    final topicText = topics.isEmpty ? (_firstText(info['节/周']) ?? '') : topics.join(' / ');
    final weekPattern = _parseWeekPattern(_firstText(info['节/周']));

    return _LessonTemplate(
      courseName: _firstText(course['title']) ?? _firstText(info['教学班名称']) ?? '课程',
      teacher: teacherLabel,
      topic: topicText,
      location: _firstText(info['上课地点']) ?? '',
      dayOffset: dayOffset,
      startTime: startSlot.start,
      endTime: endSlot.end,
      weekPattern: weekPattern,
    );
  }

  DateTime _currentWeekMonday() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  int? _parseDayOffset(dynamic columnIndex, String? cellId) {
    final normalized = _normalizeColumnIndex(columnIndex);
    if (normalized != null && normalized >= 0 && normalized <= 6) {
      return normalized;
    }
    final idDay = _parseCellIdDay(cellId);
    if (idDay != null && idDay >= 0 && idDay <= 6) {
      return idDay;
    }
    return null;
  }

  int? _normalizeColumnIndex(dynamic columnIndex) {
    if (columnIndex == null) return null;
    final raw = columnIndex is num ? columnIndex.toInt() : int.tryParse(columnIndex.toString());
    if (raw == null) return null;
    if (raw >= 0 && raw <= 6) return raw;
    if (raw >= 1 && raw <= 7) return raw - 1;
    if (raw >= 2 && raw <= 8) return raw - 2;
    return null;
  }

  int? _parseCellIdDay(String? cellId) {
    if (cellId == null) return null;
    final match = RegExp(r'(\d+)[-_](\d+)').firstMatch(cellId);
    if (match == null) return null;
    final col = int.tryParse(match.group(2)!);
    if (col == null) return null;
    if (col >= 1 && col <= 7) return col - 1;
    if (col >= 0 && col <= 6) return col;
    return null;
  }

  _SlotRange? _parseSlotRange(String? text, {int? rowSpan}) {
    if (text == null) return null;
    final normalized = text.replaceAll('（', '(').replaceAll('）', ')');
    final rangeMatch = RegExp(r'(\d+)\s*-\s*(\d+)节').firstMatch(normalized);
    if (rangeMatch != null) {
      final start = int.parse(rangeMatch.group(1)!);
      final end = int.parse(rangeMatch.group(2)!);
      return _SlotRange(start, end);
    }
    final singleMatch = RegExp(r'(\d+)节').firstMatch(normalized);
    if (singleMatch != null) {
      final start = int.parse(singleMatch.group(1)!);
      final count = rowSpan ?? 1;
      return _SlotRange(start, start + count - 1);
    }
    return null;
  }

  WeekPattern? _parseWeekPattern(String? text) {
    if (text == null) return null;
    final normalized = text.replaceAll('（', '(').replaceAll('）', ')');
    final match = RegExp(r'(\d+)(?:\s*-\s*(\d+))?周').firstMatch(normalized);
    int? start;
    int? end;
    if (match != null) {
      start = int.tryParse(match.group(1)!);
      end = match.group(2) != null ? int.tryParse(match.group(2)!) : start;
    }
    WeekParity parity = WeekParity.any;
    if (normalized.contains('单周') || normalized.contains('(单') || normalized.contains('单)')) {
      parity = WeekParity.odd;
    } else if (normalized.contains('双周') || normalized.contains('(双') || normalized.contains('双)')) {
      parity = WeekParity.even;
    }
    if (start == null && parity == WeekParity.any) return null;
    return WeekPattern(startWeek: start, endWeek: end, parity: parity);
  }

  TimeSlot? _slotByIndex(int index) {
    for (final slot in kTimeSlots) {
      if (slot.index == index) return slot;
    }
    return null;
  }

  List<String> _normalizeList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => _cleanText(e)).where((e) => e.isNotEmpty).toList();
    }
    final text = _cleanText(value);
    if (text.isEmpty) return [];
    // Try splitting by / or 、
    final parts = text.split(RegExp(r'[、/，,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? [text] : parts;
  }

  String _cleanText(dynamic value) {
    if (value == null) return '';
    return value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _firstText(dynamic value) {
    final list = _normalizeList(value);
    if (list.isNotEmpty) return list.first;
    final text = _cleanText(value);
    return text.isEmpty ? null : text;
  }
}

class _SlotRange {
  _SlotRange(this.start, this.end);
  final int start;
  final int end;
}

class _LessonTemplate {
  const _LessonTemplate({
    required this.courseName,
    required this.teacher,
    required this.topic,
    required this.location,
    required this.dayOffset,
    required this.startTime,
    required this.endTime,
    this.weekPattern,
  });

  final String courseName;
  final String teacher;
  final String topic;
  final String location;
  final int dayOffset;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final WeekPattern? weekPattern;

  Lesson buildForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day, startTime.hour, startTime.minute);
    final end = DateTime(date.year, date.month, date.day, endTime.hour, endTime.minute);
    return Lesson(
      courseName: courseName,
      teacher: teacher,
      startTime: start,
      endTime: end,
      topic: topic,
      location: location,
      weekPattern: weekPattern,
    );
  }
}

class LessonCapturePage extends StatefulWidget {
  const LessonCapturePage({
    super.key,
    required this.lesson,
    this.initialSummary,
  });

  final Lesson lesson;
  final String? initialSummary;

  @override
  State<LessonCapturePage> createState() => _LessonCapturePageState();
}

class _LessonCapturePageState extends State<LessonCapturePage> {
  late final WebViewController _controller;
  double _progress = 0;
  bool _isCapturing = false;
  final List<_CapturePiece> _segments = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialSummary != null && widget.initialSummary!.trim().isNotEmpty) {
      _segments.add(
        _CapturePiece(
          isImage: false,
          content: widget.initialSummary!.trim(),
        ),
      );
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) => setState(() => _progress = value / 100),
        ),
      )
      ..loadRequest(Uri.parse('https://oc.sjtu.edu.cn/'));
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.lesson.courseName;
    return Scaffold(
      appBar: AppBar(
        title: Text('抓取 $course'),
        actions: [
          IconButton(
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载页面',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress < 1 ? LinearProgressIndicator(value: _progress) : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          _buildInstructionBanner(),
          Expanded(child: WebViewWidget(controller: _controller)),
          _buildCapturePanel(),
        ],
      ),
    );
  }

  Widget _buildInstructionBanner() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: theme.colorScheme.primary.withOpacity(0.07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('操作提示', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('1. 登录 oc.sjtu.edu.cn ，选择对应课程。'),
          Text('2. 进入“课堂视频(NEW)”并选择今天这节课对应的点播。'),
          Text('3. 可以多次抓取或手动补充，覆盖跨两节/三节课的内容。'),
        ],
      ),
    );
  }

  Widget _buildCapturePanel() {
    final theme = Theme.of(context);
    return Material(
      elevation: 16,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isCapturing ? null : _captureFromWeb,
                      icon: _isCapturing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.copy_all_outlined),
                      label: Text(_isCapturing ? '抓取中...' : '抓取当前页面'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addManualSegment,
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('手动补充'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSegmentList(),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _segments.isEmpty ? null : _finishAndReturn,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('完成并返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentList() {
    if (_segments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('尚未添加内容，完成抓取后会出现在这里。'),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _segments.length,
        itemBuilder: (context, index) {
          final piece = _segments[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(piece.isImage ? Icons.photo_outlined : Icons.notes_outlined, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          piece.isImage ? 'PPT 图片片段' : '语音文本片段',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (piece.timeLabel != null)
                        Text(piece.timeLabel!, style: Theme.of(context).textTheme.bodySmall),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _segments.removeAt(index)),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  piece.isImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            piece.content,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              piece.content,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        )
                      : Text(
                          piece.content,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 8),
      ),
    );
  }

  Future<void> _captureFromWeb() async {
    const script = r'''
      (function() {
        function textOf(node) {
          return node && node.innerText ? node.innerText.trim() : '';
        }
        const captionCards = Array.from(document.querySelectorAll('.caption-scroll-wrapper .caption-card'));
        const captions = captionCards.map(card => ({
          time: textOf(card.querySelector('.time-wrapper')),
          text: textOf(card.querySelector('.caption-text .part') || card.querySelector('.caption-text')),
        })).filter(item => item.text);

        const imageCards = Array.from(document.querySelectorAll('.ppt-card .el-image_inner img, .ppt-card .el-image img'));
        const images = imageCards.map(img => {
          const card = img.closest('.ppt-card');
          const timeNode = card ? card.querySelector('.time') : null;
          return {
            src: img.getAttribute('src') || '',
            time: textOf(timeNode),
          };
        }).filter(item => item.src);

        return JSON.stringify({captions, images});
      })();
    ''';
    setState(() => _isCapturing = true);
    try {
      final jsResult = await _controller.runJavaScriptReturningResult(script);
      final normalized = _normalizeJsResult(jsResult).trim();
      if (normalized.isEmpty) {
        throw Exception('未获取到可用文字，请尝试展开课程内容或手动补充');
      }
      final decoded = jsonDecode(normalized) as Map<String, dynamic>;
      final captionList = (decoded['captions'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => (e['text'] as String?)?.trim().isNotEmpty ?? false)
          .toList();
      final imageList = (decoded['images'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => (e['src'] as String?)?.trim().isNotEmpty ?? false)
          .toList();

      if (captionList.isEmpty && imageList.isEmpty) {
        throw Exception('网页结构中未找到字幕或 PPT 图片，请确认已打开“语音”与 PPT 栏目。');
      }

      final combinedCaption = captionList
          .map((c) {
            final time = (c['time'] as String?)?.trim();
            final text = (c['text'] as String).trim();
            if (text.isEmpty) return '';
            return time != null && time.isNotEmpty ? '[$time] $text' : text;
          })
          .where((line) => line.isNotEmpty)
          .join('\n');

      setState(() {
        if (combinedCaption.isNotEmpty) {
          _segments.add(
            _CapturePiece(
              isImage: false,
              content: combinedCaption,
            ),
          );
        }
        for (final img in imageList) {
          _segments.add(
            _CapturePiece(
              isImage: true,
              content: (img['src'] as String).trim(),
              time: (img['time'] as String?)?.trim(),
            ),
          );
        }
      });
      if (mounted) {
        final captionSummary = captionList.isEmpty
            ? '未找到字幕'
            : '字幕 ${captionList.length} 条，已合并为 1 段';
        final imageSummary =
            imageList.isEmpty ? '未找到 PPT 图片' : 'PPT 图片 ${imageList.length} 张';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$captionSummary；$imageSummary')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('抓取失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _addManualSegment() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('手动补充要点'),
          content: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '输入课堂重点、老师强调的内容等'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('保存')),
          ],
        );
      },
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      setState(() {
        _segments.add(
          _CapturePiece(
            isImage: false,
            content: controller.text.trim(),
          ),
        );
      });
    }
  }

  void _finishAndReturn() {
    if (_segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少抓取或录入一段内容')),
      );
      return;
    }
    final textPieces = _segments.where((e) => !e.isImage).toList();
    final imagePieces = _segments.where((e) => e.isImage).toList();
    final buffer = StringBuffer();
    if (textPieces.isNotEmpty) {
      buffer.writeln('【语音摘录】');
      for (final piece in textPieces) {
        final time = piece.timeLabel != null ? '[${piece.timeLabel}] ' : '';
        buffer.writeln('$time${piece.content}');
      }
      buffer.writeln();
    }
    if (imagePieces.isNotEmpty) {
      buffer.writeln('【PPT 图片】');
      for (final piece in imagePieces) {
        final time = piece.timeLabel != null ? '[${piece.timeLabel}] ' : '';
        buffer.writeln('$time${piece.content}');
      }
    }
    Navigator.of(context).pop(buffer.toString().trim());
  }

  String _normalizeJsResult(Object raw) {
    final text = raw.toString();
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        return jsonDecode(text) as String;
      } catch (_) {
        return text;
      }
    }
    return text;
  }
}

class _CapturePiece {
  _CapturePiece({required this.isImage, required this.content, String? time})
      : timeLabel = (time != null && time.trim().isNotEmpty) ? time.trim() : null;

  final bool isImage;
  final String content;
  final String? timeLabel;
}
