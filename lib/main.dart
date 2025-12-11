import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  late ScheduleService _scheduleService;
  late Future<WeeklyScheduleOverview> _overviewFuture;
  late ScheduleRepository _repository;
  final GlobalKey<AgendaTabState> _agendaKey = GlobalKey<AgendaTabState>();
  DateTime? _termStartDate;

  @override
  void initState() {
    super.initState();
    _repository = MockScheduleRepository();
    _scheduleService = ScheduleService(repository: _repository);
    _overviewFuture = _scheduleService.loadWeekOverview(DateTime.now());
    _loadTermStartDate();
  }

  void _reload() {
    setState(() {
      _overviewFuture = _scheduleService.loadWeekOverview(DateTime.now());
    });
  }

  void _applyImportedLessons(List<Lesson> lessons) {
    setState(() {
      _repository = MemoryScheduleRepository(lessons: lessons);
      _scheduleService = ScheduleService(repository: _repository);
      _overviewFuture = _scheduleService.loadWeekOverview(DateTime.now());
      _currentIndex = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('成功导入${lessons.length}条课程，已替换课表'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openWebImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => WebImportPage(onImported: _applyImportedLessons),
      ),
    );
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

  int? _currentWeekNumber() {
    if (_termStartDate == null) return null;
    final normalizedStart = DateTime(_termStartDate!.year, _termStartDate!.month, _termStartDate!.day);
    final now = DateTime.now();
    final diff = now.difference(normalizedStart);
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

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: Text(titles[_currentIndex]),
              actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
            ),
            body: Stack(children: [gradientBackground, const Center(child: CircularProgressIndicator())]),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: Text(titles[_currentIndex]),
              actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
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
        final weekNumber = _currentWeekNumber();
        final pages = [
          TimetableTab(
            weekDays: overview.weekDays,
            currentWeekNumber: weekNumber,
            termStartDate: _termStartDate,
          ),
          AgendaTab(key: _agendaKey, items: overview.scheduleItems),
          UserTab(
            onOpenImport: _openWebImport,
            onPickTermStart: () => _pickTermStartDate(context),
            termStartDate: _termStartDate,
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
                      Text('课程表 · $weekTitle'),
                      if (startLabel != null)
                        Text(
                          '开学日：$startLabel',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  )
                : Text(titles[_currentIndex]),
            actions: [
              if (_currentIndex != 2)
                IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: '刷新数据'),
            ],
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
  });

  final List<WeekDayLessons> weekDays;
  final int? currentWeekNumber;
  final DateTime? termStartDate;

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
  });

  final List<WeekDayLessons> weekDays;
  final double timeColumnWidth;
  final double dayColumnWidth;
  final double slotHeight;
  final int? currentWeekNumber;
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
                      final remark = _formatLessonRemark(lesson.topic);
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
                                  maxLines: 3,
                                  softWrap: true,
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
}

class AgendaTab extends StatefulWidget {
  const AgendaTab({super.key, required this.items});

  final List<ScheduleItem> items;

  @override
  State<AgendaTab> createState() => AgendaTabState();
}

class AgendaTabState extends State<AgendaTab> {
  late List<ScheduleItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
  }

  void createSchedule(BuildContext context) {
    _openEditDialog(context);
  }

  void _openEditDialog(BuildContext context, {ScheduleItem? origin, int? index}) async {
    final titleCtrl = TextEditingController(text: origin?.title ?? '');
    final detailCtrl = TextEditingController(text: origin?.detail ?? '');
    DateTime selected = origin?.time ?? DateTime.now();

    Future<void> pickDateTime() async {
      final date = await showDatePicker(
        context: context,
        initialDate: selected,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (date == null) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(selected),
      );
      if (time == null) return;
      selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        );
      },
    );

    if (saved != true) return;
    final newItem = ScheduleItem(
      title: titleCtrl.text.isEmpty ? '未命名日程' : titleCtrl.text,
      detail: detailCtrl.text,
      time: selected,
      isAuto: false,
    );

    setState(() {
      if (index != null) {
        _items[index] = newItem;
      } else {
        _items.add(newItem);
      }
      _items.sort((a, b) => a.time.compareTo(b.time));
    });
  }

  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Center(child: Text('今天没有待办，保持良好作息'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
            setState(() {
              _items.removeWhere((element) => element == item);
            });
            return true;
          },
          child: _ScheduleItemCard(
            item: item,
            onEdit: () => _openEditDialog(context, origin: item, index: index),
            onDelete: () => _deleteItem(index),
          ),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: _items.length,
    );
  }
}

class UserTab extends StatelessWidget {
  const UserTab({
    super.key,
    required this.onOpenImport,
    required this.onPickTermStart,
    this.termStartDate,
  });

  final VoidCallback onOpenImport;
  final VoidCallback onPickTermStart;
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
          child: Column(
            children: [
              const _UserSettingTile(
                icon: Icons.notifications_active_outlined,
                title: '提醒设置',
                subtitle: '设置复习提醒与免打扰时段',
              ),
              const Divider(height: 1),
              const _UserSettingTile(
                icon: Icons.palette_outlined,
                title: '主题风格',
                subtitle: '选择浅色/深色模式和强调色',
              ),
            ],
          ),
        ),
      ],
    );
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
}

enum WeekParity { any, odd, even }

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

    final List<WeekDayLessons> results = [];
    final List<ReviewTask> allReviewTasks = [];

    for (final day in weekDays) {
      final lessons = await _repository.fetchLessonsForDate(day);
      results.add(WeekDayLessons(date: day, lessons: lessons));
      allReviewTasks.addAll(_planner.generatePlan(lessons));
    }

    final scheduleItems = _buildScheduleItems(allReviewTasks, anchorDay);
    return WeeklyScheduleOverview(weekDays: results, scheduleItems: scheduleItems);
  }

  List<ScheduleItem> _buildScheduleItems(List<ReviewTask> tasks, DateTime anchorDay) {
    final todayStart = DateTime(anchorDay.year, anchorDay.month, anchorDay.day);
    final todayItems = tasks
        .where((t) => _isSameDay(t.scheduledAt, todayStart))
        .map(
          (t) => ScheduleItem(
            title: '${t.courseName} · 复习',
            detail: '${t.memoryCurveLabel} | 重点：${t.focus}',
            time: t.scheduledAt,
            isAuto: true,
          ),
        )
        .toList();

    todayItems.addAll([
      ScheduleItem(
        title: '图书馆自习',
        detail: '完成高数作业 + 预习下一章',
        time: todayStart.add(const Duration(hours: 19)),
        isAuto: false,
      ),
      ScheduleItem(
        title: '社团会议',
        detail: '复盘本周活动，安排下周任务',
        time: todayStart.add(const Duration(hours: 21)),
        isAuto: false,
      ),
    ]);

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

String _formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
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
  const WebImportPage({super.key, required this.onImported});

  final ValueChanged<List<Lesson>> onImported;

  @override
  State<WebImportPage> createState() => _WebImportPageState();
}

class _WebImportPageState extends State<WebImportPage> {
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
          if (td && td.parentElement) {
            columnIndex = Array.from(td.parentElement.children).indexOf(td);
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
    final monday = _currentWeekMonday();
    final results = <Lesson>[];
    for (final course in rawCourses) {
      final lesson = _mapCourseToLesson(course, monday);
      if (lesson != null) {
        results.add(lesson);
      }
    }
    return results;
  }

  Lesson? _mapCourseToLesson(Map<String, dynamic> course, DateTime monday) {
    final info = Map<String, dynamic>.from(course['info'] as Map? ?? {});
    final rowSpan = int.tryParse('${course['rowSpan'] ?? ''}');
    final slotText = _firstText(info['节/周']) ?? _firstText(info['节次']);
    final slotRange = _parseSlotRange(slotText, rowSpan: rowSpan);
    final dayOffset = _parseDayOffset(course['columnIndex']);
    if (slotRange == null || dayOffset == null) return null;
    final startSlot = _slotByIndex(slotRange.start);
    final endSlot = _slotByIndex(slotRange.end);
    if (startSlot == null || endSlot == null) return null;

    final date = monday.add(Duration(days: dayOffset));
    final startTime = DateTime(date.year, date.month, date.day, startSlot.start.hour, startSlot.start.minute);
    final endTime = DateTime(date.year, date.month, date.day, endSlot.end.hour, endSlot.end.minute);

    final teachers = _normalizeList(info['教师']);
    final teacherLabel = teachers.isEmpty ? '' : teachers.join(' / ');

    final topics = _normalizeList(info['课程标记'] ?? info['选课备注']);
    final topicText = topics.isEmpty ? (_firstText(info['节/周']) ?? '') : topics.join(' / ');
    final weekPattern = _parseWeekPattern(_firstText(info['节/周']));

    return Lesson(
      courseName: _firstText(course['title']) ?? _firstText(info['教学班名称']) ?? '课程',
      teacher: teacherLabel,
      startTime: startTime,
      endTime: endTime,
      topic: topicText,
      location: _firstText(info['上课地点']) ?? '',
      weekPattern: weekPattern,
    );
  }

  DateTime _currentWeekMonday() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  int? _parseDayOffset(dynamic columnIndex) {
    if (columnIndex == null) return null;
    final index = columnIndex is num ? columnIndex.toInt() : int.tryParse(columnIndex.toString());
    if (index == null) return null;
    final offset = index - 2;
    if (offset < 0 || offset > 6) return null;
    return offset;
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
