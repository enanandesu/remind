import 'package:flutter/material.dart';

void main() {
  runApp(const RemindApp());
}

class RemindApp extends StatelessWidget {
  const RemindApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    );

    return MaterialApp(
      title: '复习提醒助手',
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: Colors.grey.shade50,
        textTheme: baseTheme.textTheme.apply(
          bodyColor: Colors.grey.shade900,
          displayColor: Colors.grey.shade900,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  late final ScheduleService _scheduleService;
  late Future<WeeklyScheduleOverview> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _scheduleService = ScheduleService();
    _overviewFuture = _scheduleService.loadWeekOverview(DateTime.now());
  }

  void _reload() {
    setState(() {
      _overviewFuture = _scheduleService.loadWeekOverview(DateTime.now());
    });
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

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: Text(titles[_currentIndex]),
              actions: [
                IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: Stack(
              children: [
                gradientBackground,
                const Center(child: CircularProgressIndicator()),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: Text(titles[_currentIndex]),
              actions: [
                IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
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
                      ElevatedButton(
                        onPressed: _reload,
                        child: const Text('重新获取'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final overview = snapshot.data!;
        final pages = [
          TimetableTab(weeklyLessons: overview.weeklyLessons),
          AgendaTab(items: overview.scheduleItems),
          const UserTab(),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(titles[_currentIndex]),
            actions: [
              if (_currentIndex != 2)
                IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新数据',
                ),
            ],
          ),
          body: Stack(
            children: [
              gradientBackground,
              SafeArea(
                child: IndexedStack(
                  index: _currentIndex,
                  children: pages,
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
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
  const TimetableTab({super.key, required this.weeklyLessons});

  final Map<String, List<Lesson>> weeklyLessons;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: weeklyLessons.entries.map((entry) {
        final lessons = entry.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                entry.key,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (lessons.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text('当天暂无课程，安排自习或休息'),
              ),
            ...lessons.map((lesson) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LessonCard(lesson: lesson),
                )),
          ],
        );
      }).toList(),
    );
  }
}

class AgendaTab extends StatelessWidget {
  const AgendaTab({super.key, required this.items});

  final List<ScheduleItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('今天没有待办，保持良好作息'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemBuilder: (context, index) {
        final item = items[index];
        return _ScheduleItemCard(item: item);
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: items.length,
    );
  }
}

class UserTab extends StatelessWidget {
  const UserTab({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [color.primary, color.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person_outline, size: 32, color: color.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('未登录', style: TextStyle(color: Colors.white, fontSize: 18)),
                      SizedBox(height: 6),
                      Text('登录后同步课表与复习计划', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color.primary,
                  ),
                  onPressed: () {},
                  child: const Text('登录'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: const [
                _UserSettingTile(
                  icon: Icons.notifications_active_outlined,
                  title: '提醒设置',
                  subtitle: '开启每日复习提醒，支持静音时间段',
                ),
                Divider(height: 1),
                _UserSettingTile(
                  icon: Icons.schedule_outlined,
                  title: '导入课表',
                  subtitle: '支持教务抓取或课程表文件导入',
                ),
                Divider(height: 1),
                _UserSettingTile(
                  icon: Icons.palette_outlined,
                  title: '主题风格',
                  subtitle: '选择浅色/深色和强调色',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserSettingTile extends StatelessWidget {
  const _UserSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {},
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final start = TimeOfDay.fromDateTime(lesson.startTime);
    final end = TimeOfDay.fromDateTime(lesson.endTime);
    final timeRange =
        '${localizations.formatTimeOfDay(start, alwaysUse24HourFormat: true)} - ${localizations.formatTimeOfDay(end, alwaysUse24HourFormat: true)}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(lesson.courseName, style: Theme.of(context).textTheme.titleMedium),
                Chip(
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  label: Text(
                    lesson.location,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16),
                const SizedBox(width: 4),
                Text(timeRange),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16),
                const SizedBox(width: 4),
                Text(lesson.teacher),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '课堂要点：${lesson.topic}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleItemCard extends StatelessWidget {
  const _ScheduleItemCard({required this.item});

  final ScheduleItem item;

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
          ],
        ),
      ),
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
  });

  final String courseName;
  final String teacher;
  final DateTime startTime;
  final DateTime endTime;
  final String topic;
  final String location;
}

class ReviewTask {
  ReviewTask({
    required this.courseName,
    required this.scheduledAt,
    required this.offsetFromLesson,
    required this.focus,
    this.note,
  });

  final String courseName;
  final DateTime scheduledAt;
  final Duration offsetFromLesson;
  final String focus;
  final String? note;

  String get memoryCurveLabel {
    final hours = offsetFromLesson.inHours;
    if (hours < 24) return '课后${hours}小时';
    return '课后${offsetFromLesson.inDays}天';
  }
}

class ScheduleItem {
  ScheduleItem({
    required this.title,
    required this.detail,
    required this.time,
    this.isAuto = true,
  });

  final String title;
  final String detail;
  final DateTime time;
  final bool isAuto;
}

class WeeklyScheduleOverview {
  WeeklyScheduleOverview({
    required this.weeklyLessons,
    required this.scheduleItems,
  });

  final Map<String, List<Lesson>> weeklyLessons;
  final List<ScheduleItem> scheduleItems;
}

class ScheduleService {
  ScheduleService({
    ScheduleRepository? repository,
    ReviewPlanner? planner,
  })  : _repository = repository ?? MockScheduleRepository(),
        _planner = planner ?? ReviewPlanner();

  final ScheduleRepository _repository;
  final ReviewPlanner _planner;

  Future<WeeklyScheduleOverview> loadWeekOverview(DateTime anchorDay) async {
    final monday = anchorDay.subtract(Duration(days: anchorDay.weekday - 1));
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));

    final Map<String, List<Lesson>> weeklyLessons = {};
    final List<ReviewTask> allReviewTasks = [];

    for (final day in weekDays) {
      final lessons = await _repository.fetchLessonsForDate(day);
      weeklyLessons[_weekdayLabel(day.weekday)] = lessons;
      allReviewTasks.addAll(_planner.generatePlan(lessons));
    }

    final scheduleItems = _buildScheduleItems(allReviewTasks, anchorDay);
    return WeeklyScheduleOverview(weeklyLessons: weeklyLessons, scheduleItems: scheduleItems);
  }

  List<ScheduleItem> _buildScheduleItems(List<ReviewTask> tasks, DateTime anchorDay) {
    final todayStart = DateTime(anchorDay.year, anchorDay.month, anchorDay.day);
    final todayItems = tasks
        .where((t) =>
            t.scheduledAt.year == todayStart.year &&
            t.scheduledAt.month == todayStart.month &&
            t.scheduledAt.day == todayStart.day)
        .map(
          (t) => ScheduleItem(
            title: '${t.courseName} · 复习',
            detail: '${t.memoryCurveLabel} | 重点：${t.focus}',
            time: t.scheduledAt,
            isAuto: true,
          ),
        )
        .toList();

    // 示例手动添加日程
    todayItems.addAll([
      ScheduleItem(
        title: '图书馆自习',
        detail: '完成高数作业 + 预习下一章',
        time: todayStart.add(const Duration(hours: 19, minutes: 0)),
        isAuto: false,
      ),
      ScheduleItem(
        title: '社团会议',
        detail: '复盘本周活动，安排下周任务',
        time: todayStart.add(const Duration(hours: 21, minutes: 0)),
        isAuto: false,
      ),
    ]);

    todayItems.sort((a, b) => a.time.compareTo(b.time));
    return todayItems;
  }

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
}

abstract class ScheduleRepository {
  Future<List<Lesson>> fetchLessonsForDate(DateTime date);
}

class MockScheduleRepository implements ScheduleRepository {
  @override
  Future<List<Lesson>> fetchLessonsForDate(DateTime date) async {
    await Future<void>.delayed(const Duration(milliseconds: 240));
    final dayStart = DateTime(date.year, date.month, date.day);

    // 简单示例：周一、三、五有满课，其他较少
    if (date.weekday == DateTime.tuesday) {
      return [
        Lesson(
          courseName: '职业规划',
          teacher: '周老师',
          startTime: dayStart.add(const Duration(hours: 10, minutes: 0)),
          endTime: dayStart.add(const Duration(hours: 11, minutes: 30)),
          topic: '简历与面试技巧',
          location: '学生中心201',
        ),
      ];
    }

    if (date.weekday == DateTime.thursday) {
      return [
        Lesson(
          courseName: '心理健康',
          teacher: '黄老师',
          startTime: dayStart.add(const Duration(hours: 15, minutes: 0)),
          endTime: dayStart.add(const Duration(hours: 16, minutes: 30)),
          topic: '压力管理与自我调节',
          location: '教学楼C区102',
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
        startTime: dayStart.add(const Duration(hours: 8, minutes: 0)),
        endTime: dayStart.add(const Duration(hours: 9, minutes: 40)),
        topic: '第5章 定积分与应用',
        location: '教学楼A区205',
      ),
      Lesson(
        courseName: '大学英语',
        teacher: '李老师',
        startTime: dayStart.add(const Duration(hours: 10, minutes: 10)),
        endTime: dayStart.add(const Duration(hours: 11, minutes: 40)),
        topic: 'Unit 6 Reading Skills',
        location: '教学楼B区308',
      ),
      Lesson(
        courseName: '数据结构',
        teacher: '陈老师',
        startTime: dayStart.add(const Duration(hours: 14, minutes: 0)),
        endTime: dayStart.add(const Duration(hours: 15, minutes: 40)),
        topic: '第3章 栈与队列',
        location: '信息楼C区101',
      ),
    ];
  }
}

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
          ),
        );
      }
    }
    tasks.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return tasks;
  }

  String? _buildSuggestion(Duration interval) {
    if (interval.inHours <= 6) {
      return '快速回顾课堂笔记，标记不确定点。';
    } else if (interval.inDays <= 1) {
      return '完成配套习题，检查理解的准确性。';
    } else if (interval.inDays <= 3) {
      return '整理错题与难点，尝试讲解给同伴听。';
    } else if (interval.inDays <= 7) {
      return '结合记忆曲线回顾核心知识，准备下阶段学习。';
    }
    return null;
  }
}
