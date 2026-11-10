// =============================================================================
//  Streak · 多项目打卡
//  ---------------------------------------------------------------------------
//  结构：
//    HomePage      左右滑动切换项目（PageView）+ 极小的项目指示器
//    ProjectPage   单个项目：超大连续数字 → 打卡按钮 → 无缝下拉日历
//    NotePage      极简记事（按项目、按日期存）
//    _DaySheet     点日历某一天，弹出当天的打卡详情（几点几分 / 未打卡）
//
//  关于「日历是动态的」：
//    日历不是渲染好的图片，每次都由 DateTime.now() 现算：
//      · 行 = 以周一到周日切片，从 18 个月前一直排到 8 个月后
//      · 今天 = 每次启动时取系统日期，跨过零点或从后台切回来会重新取
//      · 每一天的打卡状态、记事小圆点，都从 checkIns / notes 里实时读
//    所以只要系统日期是真的，日历就是真的。
//
//  三条产品规则：
//    1. 每个项目一条独立的 streak，互不干扰。
//    2. 断卡后 6 天内可以补签，一次性把缺口补齐，天数接回原处；
//       超过 6 天就真的断了，数字清零，从今天重新开始。
//    3. 每个项目自带 6 张补签额度，补一天消耗一张。补完为止。
//
//  关于「桌面点弹窗直接打卡」：
//    入口已经留好了 —— AppStore.quickCheckIn(habitId)。Android AppWidget、
//    iOS Widget、通知按钮、快捷指令，只要拿到项目 id 调它一次即可，
//    数据与界面会自动同步，不需要打开 App 的任何页面。
//    原生侧接入步骤见 quickCheckIn 上方的注释。
//
//  依赖：只用 Flutter SDK，不需要任何第三方插件。
// =============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const StreakApp());

// -----------------------------------------------------------------------------
// 设计常量
// -----------------------------------------------------------------------------
const Color _ink = Color(0xFF111111); // 主黑
const Color _inkSoft = Color(0xFF9A9A9A); // 次级灰
const Color _hairline = Color(0xFFEAEAEA); // 极淡描边
const Color _shadow = Color(0x2E000000); // 18% 黑，阴影

const double _kWeekRowHeight = 54; // 一行日期的固定高度
const double _kMonthLabelHeight = 46; // 月份标签的固定高度
// 这两个常量同时被「列表渲染」和「初始滚动位置计算」使用，
// 必须和 _buildRow 里的 SizedBox 高度严格一致，否则首屏定位会偏。

const int _kGraceDays = 6; // 断卡后多少天内还能补
const int _kMakeupCards = 6; // 每个项目初始补签额度（一天一张）

class StreakApp extends StatelessWidget {
  const StreakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Streak',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        splashFactory: NoSplash.splashFactory, // 极简风：去掉水波纹
      ),
      home: const HomePage(),
    );
  }
}

// =============================================================================
//  数据层
// =============================================================================

/// 一次打卡的记录。
///
/// 只存「时刻」而不是「日期」，因为日历详情里要精确显示 08:30；
/// 日期本身由 [Habit.checkIns] 的 key 承担。
class CheckIn {
  const CheckIn({required this.at, this.makeup = false});

  /// 打卡发生的真实时间点
  final DateTime at;

  /// 是不是补签的。补签的日子没有「当时那一秒」，所以要分开标注。
  final bool makeup;

  /// 08:30 这样的显示格式
  String get clock {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 一个打卡项目。
class Habit {
  Habit({
    required this.id,
    required this.name,
    required this.glyph,
    Map<String, CheckIn>? checkIns,
    Map<String, String>? notes,
    this.makeupCards = _kMakeupCards,
  })  : checkIns = checkIns ?? <String, CheckIn>{},
        notes = notes ?? <String, String>{};

  final String id;
  final String name;

  /// 极简标识：一个汉字，只用在项目列表里
  final String glyph;

  /// 已打卡的日期 → 打卡记录，key 是 yyyy-MM-dd
  final Map<String, CheckIn> checkIns;

  /// 记事，日期 → 内容
  final Map<String, String> notes;

  /// 剩余补签额度
  int makeupCards;

  // ---------------------------------------------------------------- 便捷判断
  bool hasKey(String dayKey) => checkIns.containsKey(dayKey);

  bool has(DateTime day) => checkIns.containsKey(AppStore.key(day));

  CheckIn? at(DateTime day) => checkIns[AppStore.key(day)];

  /// 记一次打卡。[at] 缺省就用当前时间，补签传 makeup: true。
  void mark(DateTime day, {DateTime? at, bool makeup = false}) {
    checkIns[AppStore.key(day)] = CheckIn(
      at: at ?? DateTime.now(),
      makeup: makeup,
    );
  }
}

/// 本地存储。
///
/// 现在是纯内存模拟，接口刻意做成异步，方便替换成真正的本地数据库：
///
/// ```dart
/// // pubspec.yaml
/// //   sqflite: ^2.3.3
/// //   path: ^1.9.0
/// //
/// // 表结构建议：
/// //   habit(id TEXT PRIMARY KEY, name TEXT, glyph TEXT,
/// //         cards INT, sort INT)
/// //   checkin(habit_id TEXT, day TEXT,
/// //           at TEXT,            -- 打卡时刻 ISO8601，用于详情里显示 08:30
/// //           makeup INT,         -- 1 = 补签
/// //           PRIMARY KEY(habit_id, day))
/// //   note(habit_id TEXT, day TEXT, content TEXT,
/// //        PRIMARY KEY(habit_id, day))
/// ```
class AppStore {
  AppStore._();

  static final AppStore instance = AppStore._();

  final List<Habit> _habits = <Habit>[];

  List<Habit> get habits => List<Habit>.unmodifiable(_habits);

  /// 以 yyyy-MM-dd 作为日期主键，避免 DateTime 的时分秒干扰比较。
  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Habit? byId(String id) {
    for (final h in _habits) {
      if (h.id == id) return h;
    }
    return null;
  }

  Future<void> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (_habits.isNotEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime back(int n) => DateTime(today.year, today.month, today.day - n);

    // 给模拟数据编一个「那一天几点几分打的卡」。
    // 用天数做种子，保证每次启动看到的时间一致，不像每次都重新随机。
    DateTime stamp(int daysAgo, int baseHour, int span) => DateTime(
          today.year,
          today.month,
          today.day - daysAgo,
          baseHour + (daysAgo * 7) % span,
          (daysAgo * 17) % 60,
        );

    // ---------------- 项目一：早起（今天还没打，点一下就是 350 → 351）
    final early = Habit(id: 'early', name: '早起', glyph: '早');
    for (var i = 1; i <= 350; i++) {
      early.mark(back(i), at: stamp(i, 5, 4)); // 05:00–08:59
    }
    // 再往前撒一些散点，让日历看起来有真实的断续感。
    // 从第 355 天开始，硬留 4 天空档，否则连续段会被接上变成 351。
    final rnd = math.Random(20261109);
    for (var i = 355; i <= 470; i++) {
      if (rnd.nextDouble() < 0.55) {
        early.mark(back(i), at: stamp(i, 5, 4));
      }
    }
    early.notes[key(back(1))] = '早上跑步 5km';
    early.notes[key(back(3))] = '状态不错，继续。';

    // ---------------- 项目二：阅读（断卡 2 天，演示补签）
    final read = Habit(id: 'read', name: '阅读', glyph: '读');
    for (var i = 3; i <= 14; i++) {
      read.mark(back(i), at: stamp(i, 20, 4)); // 20:00–23:59
    }
    for (var i = 20; i <= 26; i++) {
      read.mark(back(i), at: stamp(i, 20, 4));
    }
    read.notes[key(back(5))] = '《人类简史》第 4 章';

    // ---------------- 项目三：健身（断卡 9 天，已清零）
    final fit = Habit(id: 'fit', name: '健身', glyph: '健');
    for (var i = 10; i <= 15; i++) {
      fit.mark(back(i), at: stamp(i, 18, 3)); // 18:00–20:59
    }

    _habits
      ..add(early)
      ..add(read)
      ..add(fit);
  }

  // ---------------------------------------------------------------- 写操作
  Habit addHabit(String name) {
    final t = name.trim();
    final h = Habit(
      id: 'h${DateTime.now().microsecondsSinceEpoch}',
      name: t,
      glyph: t.isEmpty ? '新' : t.substring(0, 1),
      makeupCards: _kMakeupCards,
    );
    _habits.add(h);
    return h;
  }

  void removeHabit(String id) {
    _habits.removeWhere((h) => h.id == id);
  }

  void addCheckIn(Habit h, DateTime day) {
    h.mark(day);
  }

  void saveNote(Habit h, DateTime day, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      h.notes.remove(key(day));
    } else {
      h.notes[key(day)] = t;
    }
  }

  /// 桌面小组件 / 通知按钮 / 快捷指令的统一入口。
  ///
  /// ```dart
  /// // 1. pubspec.yaml
  /// //      home_widget: ^0.6.0
  /// //
  /// // 2. main() 里注册一次回调，原生点一下就会走到这里
  /// //    HomeWidget.registerInteractivityCallback(quickCheckInFromWidget);
  /// //
  /// // 3. 原生侧（Android AppWidgetProvider / iOS Widget）收到点击后：
  /// //    HomeWidgetBackgroundIntent.getBroadcast(context,
  /// //        Uri.parse('streak://checkin?habit=early')).send()
  /// //
  /// // 4. 每次打卡后把状态写回小组件，让桌面上的数字立刻变：
  /// //    HomeWidget.saveWidgetData<String>('streak_early', '351');
  /// //    HomeWidget.updateWidget(androidName: 'StreakWidgetProvider');
  /// ```
  ///
  /// 返回 false 表示项目不存在或今天已经打过。
  Future<bool> quickCheckIn(String habitId) async {
    final h = byId(habitId);
    if (h == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (h.has(today)) return false;

    h.mark(today, at: now);
    return true;
  }
}

// -----------------------------------------------------------------------------
// 连续天数
// -----------------------------------------------------------------------------

/// 一次连续天数计算的结果。
class StreakInfo {
  const StreakInfo({
    required this.days,
    this.gap = 0,
    this.makable = false,
    this.broken = false,
  });

  /// 显示在屏幕中央的数字
  final int days;

  /// 与上一段之间断掉的天数（0 表示没断）
  final int gap;

  /// 现在能不能一键补签
  final bool makable;

  /// 已经彻底断了（断卡超过宽限期）
  final bool broken;

  /// 补签之后会变成多少天
  int get restored => days + gap;
}

/// 计算规则：
///   今天打了 → 从今天往前数；
///   今天没打 → 从昨天往前数（今天的打卡机会还在，不算断）。
/// 数到头之后看前面有没有缺口：缺口 ≤ 6 天就还可以补签，补完接回原处。
StreakInfo computeStreak(Habit h, DateTime today) {
  bool has(DateTime d) => h.has(d);
  DateTime shift(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  // ① 当前连续段
  var cursor = today;
  if (!has(cursor)) cursor = shift(cursor, -1);

  var n = 0;
  while (has(cursor)) {
    n++;
    cursor = shift(cursor, -1);
  }

  // 今天（或昨天）还在连，一切正常，不需要补签
  if (n > 0) return StreakInfo(days: n);

  // ② 今天和昨天都没打 —— 量一下缺口有多长
  var p = shift(today, -1);
  var gap = 0;
  while (gap <= _kGraceDays && !has(p)) {
    gap++;
    p = shift(p, -1);
  }

  // 缺口超过宽限期：彻底断了
  if (gap > _kGraceDays) return const StreakInfo(days: 0, broken: true);

  // ③ 缺口之前还有一段吗？没有的话就是从头开始
  var prev = 0;
  while (has(p)) {
    prev++;
    p = shift(p, -1);
  }
  if (prev == 0) return const StreakInfo(days: 0, broken: true);

  return StreakInfo(
    days: prev,
    gap: gap,
    makable: h.makeupCards >= gap,
  );
}

// =============================================================================
//  首页：横向分页
// =============================================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final AppStore _store = AppStore.instance;
  final PageController _pager = PageController();

  /// 「今天」整个 App 只在这里算一次，然后往下传。
  /// 它是可变的：跨过零点、或者从后台切回来时会重新取一次系统日期。
  late DateTime _today;

  /// 零点定时器：挂在下一个 00:00，触发后重新排一次。
  Timer? _midnight;

  bool _loading = true;
  int _index = 0;
  List<Habit> _habits = const <Habit>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = _todayFromClock();
    _scheduleMidnight();
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _pager.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 日期跟随
  static DateTime _todayFromClock() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// 挂到「下一个零点 + 2 秒」，避免刚好卡在 23:59:59.999 上抖动。
  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 2), () {
      _refreshToday();
      _scheduleMidnight();
    });
  }

  /// 从后台切回来时也要对一次表 —— 手机睡觉时定时器不一定会准时跑。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshToday();
      _scheduleMidnight();
    }
  }

  void _refreshToday() {
    final t = _todayFromClock();
    if (t == _today) return;
    if (!mounted) return;
    setState(() => _today = t);
  }

  Future<void> _bootstrap() async {
    await _store.load();
    if (!mounted) return;
    setState(() {
      _habits = List<Habit>.of(_store.habits);
      _loading = false;
    });
  }

  void _sync() {
    setState(() => _habits = List<Habit>.of(_store.habits));
  }

  // ---------------------------------------------------------------- 项目面板
  Future<void> _openSwitcher() async {
    if (_habits.isEmpty) return;
    final r = await showModalBottomSheet<_SheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x1A000000),
      isScrollControlled: true,
      builder: (_) => _HabitSheet(
        habits: _habits,
        currentId: _habits[_index].id,
        today: _today,
      ),
    );
    if (r == null || !mounted) return;

    if (r.action == _SheetAction.select) {
      final i = _habits.indexWhere((h) => h.id == r.id);
      if (i >= 0 && i != _index) {
        setState(() => _index = i);
        if (_pager.hasClients) _pager.jumpToPage(i);
      }
    } else if (r.action == _SheetAction.create) {
      final name = await _askName();
      if (name == null || !mounted) return;
      _store.addHabit(name);
      _sync();
      final i = _habits.length - 1;
      setState(() => _index = i);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pager.hasClients) _pager.jumpToPage(i);
      });
    } else if (r.action == _SheetAction.delete && r.id != null) {
      _store.removeHabit(r.id!);
      final next = List<Habit>.of(_store.habits);
      var i = _index;
      if (i > next.length - 1) i = next.length - 1;
      if (i < 0) i = 0;
      setState(() {
        _habits = next;
        _index = i;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pager.hasClients && next.isNotEmpty) _pager.jumpToPage(i);
      });
    }
  }

  Future<String?> _askName() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || name.isEmpty) return null;
    return name;
  }

  // ---------------------------------------------------------------- 构建
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                ),
              )
            : (_habits.isEmpty
                ? const Center(
                    child: Text(
                      '还没有项目',
                      style: TextStyle(fontSize: 13, color: _inkSoft),
                    ),
                  )
                : PageView.builder(
                    controller: _pager,
                    // 横向滑动手感：跟系统分页一致，但保留一点回弹
                    physics: const PageScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    onPageChanged: (i) => setState(() => _index = i),
                    itemCount: _habits.length,
                    itemBuilder: (context, i) {
                      final h = _habits[i];
                      return ProjectPage(
                        key: ValueKey<String>(h.id),
                        habit: h,
                        today: _today,
                        index: i,
                        count: _habits.length,
                        onOpenSwitcher: _openSwitcher,
                      );
                    },
                  )),
      ),
    );
  }
}

// =============================================================================
//  单个项目页
// =============================================================================
class ProjectPage extends StatefulWidget {
  const ProjectPage({
    super.key,
    required this.habit,
    required this.today,
    required this.index,
    required this.count,
    required this.onOpenSwitcher,
  });

  final Habit habit;
  final DateTime today;
  final int index;
  final int count;
  final VoidCallback onOpenSwitcher;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage>
    with AutomaticKeepAliveClientMixin {
  late String _todayKey;
  late List<_CalRow> _rows;
  late ScrollController _scroll;
  late StreakInfo _info;

  /// 每打卡成功一次 +1，用来触发「今天」那个绿圈的弹一下。
  int _bumpToken = 0;

  @override
  bool get wantKeepAlive => true; // 左右滑动时保住日历滚动位置和数字状态

  @override
  void initState() {
    super.initState();
    _todayKey = AppStore.key(widget.today);
    _rows = _buildRows(widget.today);
    _info = computeStreak(widget.habit, widget.today);
    _scroll = ScrollController(
      initialScrollOffset: _offsetOf(_rows, _indexOfMonth(_rows, widget.today)),
    );
  }

  @override
  void didUpdateWidget(covariant ProjectPage old) {
    super.didUpdateWidget(old);
    // 跨过零点（或从后台切回来）时，日历要跟着换一天：
    // 重新生成日期行、重算连续天数、把视口拉回新的「本月」。
    if (old.today != widget.today) {
      _todayKey = AppStore.key(widget.today);
      _rows = _buildRows(widget.today);
      _info = computeStreak(widget.habit, widget.today);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(
          _offsetOf(_rows, _indexOfMonth(_rows, widget.today)),
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _checkedToday => widget.habit.hasKey(_todayKey);

  void _refresh() {
    setState(() => _info = computeStreak(widget.habit, widget.today));
  }

  // ---------------------------------------------------------------- 打卡
  void _checkIn() {
    if (_checkedToday) return;
    HapticFeedback.mediumImpact();

    // 断卡但还在补签窗口里：先把缺口补上，再打今天的卡。
    // 否则「打卡」会把前面那一整段历史清零，12 天直接变成 1 天。
    final info = _info;
    if (info.gap > 0 && info.makable) _fillGap(info.gap);

    widget.habit.mark(widget.today); // 记的是真实打卡时刻
    _bumpToken++;
    _refresh();
  }

  /// 把今天往前 [gap] 天全部补成已打卡，并扣掉对应额度。
  void _fillGap(int gap) {
    final now = DateTime.now();
    for (var i = 1; i <= gap; i++) {
      widget.habit.mark(
        DateTime(widget.today.year, widget.today.month, widget.today.day - i),
        at: now,
        makeup: true, // 补签的日子，详情里要标明「补签」而不是「打卡成功」
      );
    }
    widget.habit.makeupCards = math.max(0, widget.habit.makeupCards - gap);
  }

  // ---------------------------------------------------------------- 补签
  void _makeup() {
    final info = _info;
    if (!info.makable || info.gap == 0) return;
    HapticFeedback.mediumImpact();
    _fillGap(info.gap);
    _bumpToken++;
    _refresh();
  }

  // ---------------------------------------------------------------- 记事
  Future<bool> _openNote([DateTime? date]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => NotePage(habit: widget.habit, date: date ?? widget.today),
      ),
    );
    if (changed == true && mounted) setState(() {}); // 刷新日历上的记事小圆点
    return changed == true;
  }

  // ---------------------------------------------------------------- 某天详情
  /// 点日历上的某一天，弹一个极简的底部详情：几点打的卡 / 未打卡 / 那天的记事。
  Future<void> _openDay(DateTime day) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x14000000),
      isScrollControlled: false,
      builder: (_) => _DaySheet(
        habit: widget.habit,
        day: day,
        isToday: AppStore.key(day) == _todayKey,
        isFuture: day.isAfter(widget.today),
        onOpenNote: () async {
          Navigator.of(context).pop();
          await _openNote(day);
        },
      ),
    );
  }

  // ---------------------------------------------------------------- 日历数据
  List<_CalRow> _buildRows(DateTime today) {
    const int monthsBack = 18;
    const int monthsForward = 8;

    final firstMonth = DateTime(today.year, today.month - monthsBack, 1);
    final lastMonth = DateTime(today.year, today.month + monthsForward, 1);
    final lastDay = DateTime(lastMonth.year, lastMonth.month + 1, 0);

    // 从第一个月的 1 号往回退到最近的周一，保证每一行都是完整的周一到周日
    var cursor = firstMonth.subtract(Duration(days: firstMonth.weekday - 1));

    final rows = <_CalRow>[];
    while (!cursor.isAfter(lastDay)) {
      final days = List<DateTime>.generate(
        7,
        (i) => DateTime(cursor.year, cursor.month, cursor.day + i),
      );

      // 这一周里出现「1 号」，就在它上面插一条月份标签
      DateTime? label;
      for (final d in days) {
        if (d.day == 1) {
          label = DateTime(d.year, d.month, 1);
          break;
        }
      }

      rows.add(_CalRow(days: days, monthLabel: label));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 7);
    }
    return rows;
  }

  int _indexOfMonth(List<_CalRow> rows, DateTime today) {
    for (var i = 0; i < rows.length; i++) {
      final l = rows[i].monthLabel;
      if (l != null && l.year == today.year && l.month == today.month) return i;
    }
    return 0;
  }

  double _offsetOf(List<_CalRow> rows, int index) {
    var h = 0.0;
    for (var i = 0; i < index && i < rows.length; i++) {
      h += _kWeekRowHeight +
          (rows[i].monthLabel != null ? _kMonthLabelHeight : 0.0);
    }
    return h;
  }

  // ---------------------------------------------------------------- 构建
  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        // 顶部核心区约占上半屏，超大数字随可用高度自适应
        final headerH = math.min(h * 0.44, 400.0);
        final numberSize = (headerH * 0.32).clamp(76.0, 122.0).toDouble();

        return Column(
          children: [
            _buildTopBar(),
            SizedBox(height: headerH, child: _buildHeader(numberSize)),
            _buildWeekHeader(),
            Expanded(child: _buildCalendar()),
          ],
        );
      },
    );
  }

  // 顶部：项目名 + 项目指示器 + 一支笔
  Widget _buildTopBar() {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 22),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenSwitcher,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.habit.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: _inkSoft,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    for (var i = 0; i < widget.count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.only(right: 5),
                        width: i == widget.index ? 13 : 4,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: i == widget.index
                              ? _ink
                              : const Color(0xFFDCDCDC),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          _QuietIcon(icon: Icons.edit_outlined, onTap: () => _openNote()),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _buildHeader(double numberSize) {
    return Column(
      children: [
        const Spacer(flex: 5),
        RollingNumber(value: _info.days, fontSize: numberSize),
        const SizedBox(height: 10),
        // letterSpacing 会在最后一个字后面也留出间距，所以左边补一点让它真正居中
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Text(
            '连续天数',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 6,
              fontWeight: FontWeight.w500,
              color: _inkSoft,
            ),
          ),
        ),
        const Spacer(flex: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56),
          child: CheckInButton(checked: _checkedToday, onTap: _checkIn),
        ),
        const SizedBox(height: 12),
        // 固定高度，让补签提示出现/消失时上方数字不会跳
        SizedBox(height: 30, child: Center(child: _buildHint())),
      ],
    );
  }

  Widget _buildHint() {
    final info = _info;

    if (info.broken) {
      return const Text(
        '已断卡 · 从今天重新开始',
        style: TextStyle(
          fontSize: 11.5,
          color: Color(0xFFB5B5B5),
          letterSpacing: 0.4,
        ),
      );
    }

    if (info.gap == 0) return const SizedBox.shrink();

    if (!info.makable) {
      return Text(
        '断卡 ${info.gap} 天 · 补签额度不足',
        style: const TextStyle(
          fontSize: 11.5,
          color: Color(0xFFB5B5B5),
          letterSpacing: 0.4,
        ),
      );
    }

    // 可补签：一颗很轻的胶囊
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _makeup,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '断卡 ${info.gap} 天',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF8A8A8A),
                fontWeight: FontWeight.w500,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(width: 1, height: 9, color: const Color(0xFFD8D8D8)),
            ),
            Text(
              '补签恢复 ${info.restored}',
              style: const TextStyle(
                fontSize: 11.5,
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekHeader() {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFBDBDBD),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return ListView.builder(
      controller: _scroll,
      // 上下都能回弹，下拉时的手感更接近原生极简 App
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.only(bottom: 48),
      itemCount: _rows.length,
      itemBuilder: (context, index) => _buildRow(_rows[index]),
    );
  }

  Widget _buildRow(_CalRow row) {
    final label = row.monthLabel;
    // 该行所属的“主月份”，用来把上/下个月的溢出日期压淡
    final refMonth = label ?? row.days.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          SizedBox(
            height: _kMonthLabelHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${label.year}年 ${label.month}月',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _inkSoft,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
        SizedBox(
          height: _kWeekRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                for (final d in row.days)
                  Expanded(child: _buildDayCell(d, refMonth)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayCell(DateTime day, DateTime refMonth) {
    final isToday =
        day.year == widget.today.year &&
        day.month == widget.today.month &&
        day.day == widget.today.day;
    final inMonth = day.year == refMonth.year && day.month == refMonth.month;
    final checked = widget.habit.has(day);
    final noted = inMonth && widget.habit.notes.containsKey(AppStore.key(day));

    // —— 三种状态 ——
    // 未打卡：浅灰 → 已打卡：纯黑加粗 → 今天：绿底白字
    Color color;
    FontWeight weight;
    if (isToday) {
      color = Colors.white;
      weight = FontWeight.w800;
    } else if (!inMonth) {
      color = const Color(0xFFEDEDED); // 非本月，压到几乎看不见
      weight = FontWeight.w500;
    } else if (checked) {
      color = _ink;
      weight = FontWeight.w700;
    } else {
      color = Colors.grey[300]!;
      weight = FontWeight.w500;
    }

    final circle = Container(
      width: 40,
      height: 40,
      decoration: isToday
          ? const BoxDecoration(color: Colors.green, shape: BoxShape.circle)
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 21,
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.0,
                  fontWeight: weight,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 11,
            child: Center(
              child: isToday
                  ? const Text(
                      '今天',
                      style: TextStyle(
                        fontSize: 8,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                        color: Color(0xCCFFFFFF),
                        letterSpacing: 0.5,
                      ),
                    )
                  : (noted
                      ? Container(
                          width: 3.5,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: checked
                                ? const Color(0xFFB0B0B0)
                                : const Color(0xFFDCDCDC),
                            shape: BoxShape.circle,
                          ),
                        )
                      : null),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDay(day),
      child: Center(
        child: isToday
            // 打卡成功 / 补签成功后，让「今天」轻轻弹一下，给一次局部反馈
            ? TweenAnimationBuilder<double>(
                key: ValueKey<int>(_bumpToken),
                tween: Tween<double>(
                  begin: _bumpToken > 0 ? 1.28 : 1.0,
                  end: 1.0,
                ),
                duration: const Duration(milliseconds: 460),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: circle,
              )
            : circle,
      ),
    );
  }
}

// =============================================================================
//  某一天的详情（底部弹窗）
// =============================================================================
class _DaySheet extends StatelessWidget {
  const _DaySheet({
    required this.habit,
    required this.day,
    required this.isToday,
    required this.isFuture,
    required this.onOpenNote,
  });

  final Habit habit;
  final DateTime day;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onOpenNote;

  static const List<String> _week = ['一', '二', '三', '四', '五', '六', '日'];

  String get _dateLine =>
      '${day.year}年${day.month}月${day.day}日 · 周${_week[day.weekday - 1]}';

  @override
  Widget build(BuildContext context) {
    final rec = habit.at(day);
    final note = habit.notes[AppStore.key(day)];
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // 四种情况只改这两行字，其余排版完全一致，弹窗高度不会跳。
    final String big;
    final String sub;
    final double bigSize;
    final Color bigColor;
    if (isFuture) {
      big = '—';
      sub = '这一天还没到';
      bigSize = 40;
      bigColor = const Color(0xFFDCDCDC);
    } else if (rec == null) {
      big = '未打卡';
      sub = isToday ? '今天还没打卡' : '那天没有打卡记录';
      bigSize = 30;
      bigColor = const Color(0xFFC9C9C9);
    } else if (rec.makeup) {
      big = '补签';
      sub = '${rec.at.month}月${rec.at.day}日 ${rec.clock} 补上';
      bigSize = 34;
      bigColor = _ink;
    } else {
      big = rec.clock;
      sub = '打卡成功';
      bigSize = 46;
      bigColor = _ink;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 34,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE6E6E6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dateLine,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _inkSoft,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                _QuietIcon(icon: Icons.edit_outlined, onTap: onOpenNote),
              ],
            ),
          ),
          SizedBox(
            height: 112,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    big,
                    style: TextStyle(
                      fontSize: bigSize,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: bigColor,
                      letterSpacing: rec == null ? 2 : 0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.0,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFAEAEAE),
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (note != null && note.isNotEmpty) ...[
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              color: _hairline,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '记 事',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFBDBDBD),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    note,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.65,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
//  打卡按钮
// =============================================================================
class CheckInButton extends StatefulWidget {
  const CheckInButton({super.key, required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  State<CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<CheckInButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final checked = widget.checked;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: checked ? null : (_) => setState(() => _down = true),
      onTapUp: checked ? null : (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: checked ? null : widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.955 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          height: 64,
          decoration: BoxDecoration(
            color: checked ? Colors.white : _ink,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: checked ? _hairline : Colors.transparent,
              width: 1.2,
            ),
            boxShadow: checked
                ? null
                : const [
                    BoxShadow(
                      color: _shadow,
                      blurRadius: 26,
                      spreadRadius: -6,
                      offset: Offset(0, 12),
                    ),
                  ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Row(
                key: ValueKey<bool>(checked),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (checked) ...[
                    const Icon(Icons.check_rounded, size: 17, color: _ink),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    checked ? '今日已打卡' : '打 卡',
                    style: TextStyle(
                      fontSize: checked ? 14 : 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: checked ? 1.2 : 4,
                      color: checked ? _ink : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  超大滚动数字（里程表式逐位滚动）
// =============================================================================
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    super.key,
    required this.value,
    required this.fontSize,
    this.color = _ink,
  });

  final int value;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = value.abs().toString();
    final digits = text.split('').map(int.parse).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < digits.length; i++)
          _RollingDigit(
            // 位数不变时 key 不变 → 复用 State，只滚变化的位
            key: ValueKey<String>('d${digits.length}-$i'),
            digit: digits[i],
            fontSize: fontSize,
            color: color,
            // 首位先停，末位后停，像老虎机一样依次落定
            delay: Duration(milliseconds: 70 * i),
          ),
      ],
    );
  }
}

class _RollingDigit extends StatefulWidget {
  const _RollingDigit({
    super.key,
    required this.digit,
    required this.fontSize,
    required this.color,
    required this.delay,
  });

  final int digit;
  final double fontSize;
  final Color color;
  final Duration delay;

  @override
  State<_RollingDigit> createState() => _RollingDigitState();
}

class _RollingDigitState extends State<_RollingDigit>
    with SingleTickerProviderStateMixin {
  static const Duration _rollDuration = Duration(milliseconds: 560);

  late final AnimationController _c;
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _rollDuration);
    _to = widget.digit.toDouble();
    // 首帧从「本轮数字 - 10」的位置滚上来：像老虎机一样落定
    _from = _to - 10;
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 连续位置：整数部分是当前占位，小数部分是滚动进度
  double get _pos =>
      _from + (_to - _from) * Curves.easeOutCubic.transform(_c.value);

  @override
  void didUpdateWidget(covariant _RollingDigit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.digit == widget.digit) return;

    final base = _pos.round();
    var delta = (widget.digit - base % 10) % 10;
    if (delta < 0) delta += 10;
    if (delta == 0) return; // 上一次的滚动还没停稳，等它自然结束

    // 走最短路：+1 必然向上滚，9→0 也继续向上进位，符合里程表的手感
    final target = delta <= 5 ? base + delta : base - (10 - delta);

    _from = _pos;
    _to = target.toDouble();
    _c
      ..duration = _rollDuration
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.fontSize;
    final style = TextStyle(
      fontSize: cell,
      height: 1.0,
      fontWeight: FontWeight.w800,
      color: widget.color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return SizedBox(
      width: cell * 0.62,
      height: cell,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final pos = _pos;
            final index = pos.floor();
            final frac = pos - index;
            // 只画两格：当前位 + 下一位，滚动过程中始终覆盖可视区域
            return Stack(
              children: [
                for (var k = 0; k < 2; k++)
                  Positioned(
                    left: 0,
                    right: 0,
                    height: cell,
                    top: (k - frac) * cell,
                    child: Center(
                      child: Text('${(index + k) % 10}', style: style),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
//  日历行模型
// =============================================================================
class _CalRow {
  const _CalRow({required this.days, this.monthLabel});

  /// 固定 7 天，周一 → 周日
  final List<DateTime> days;

  /// 非空表示这一行上面要插一条月份标签
  final DateTime? monthLabel;
}

// =============================================================================
//  安静的图标按钮
// =============================================================================
class _QuietIcon extends StatelessWidget {
  const _QuietIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Center(
            child: Icon(icon, size: 19, color: const Color(0xFF8E8E8E)),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  项目面板（底部弹出）
// =============================================================================
enum _SheetAction { select, create, delete }

class _SheetResult {
  const _SheetResult(this.action, [this.id]);
  const _SheetResult.select(this.id) : action = _SheetAction.select;
  const _SheetResult.delete(this.id) : action = _SheetAction.delete;

  final _SheetAction action;
  final String? id;
}

/// 新建项目的小输入框。
/// 控制器由组件自己持有、在 dispose 里释放 —— 如果放在外面 await 之后再
/// dispose，退出动画期间 TextField 还在用它会直接报错。
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '新项目',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              cursorColor: _ink,
              maxLength: 8,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 16, color: _ink),
              decoration: const InputDecoration(
                counterText: '',
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '比如：早起、阅读、健身',
                hintStyle: TextStyle(fontSize: 15, color: Color(0xFFC9C9C9)),
              ),
              onSubmitted: (_) => _submit(),
            ),
            Container(
              height: 1,
              color: _hairline,
              margin: const EdgeInsets.only(top: 14),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF9A9A9A),
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: _submit,
                  style: TextButton.styleFrom(
                    foregroundColor: _ink,
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text(
                    '创建',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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

class _HabitSheet extends StatefulWidget {
  const _HabitSheet({
    required this.habits,
    required this.currentId,
    required this.today,
  });

  final List<Habit> habits;
  final String currentId;
  final DateTime today;

  @override
  State<_HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends State<_HabitSheet> {
  String? _pendingDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 40,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4E4E4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              for (final h in widget.habits) _buildRow(h),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(height: 1, color: _hairline),
              ),
              _buildCreateRow(),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(Habit h) {
    final selected = h.id == widget.currentId;
    final info = computeStreak(h, widget.today);
    final deleting = _pendingDelete == h.id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: deleting
          ? null
          : () => Navigator.of(context).pop(_SheetResult.select(h.id)),
      child: SizedBox(
        height: 62,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _ink : const Color(0xFFF3F3F3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  h.glyph,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF6E6E6E),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  h.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                '${info.days}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 3),
              const Text(
                '天',
                style: TextStyle(fontSize: 11, color: Color(0xFFB0B0B0)),
              ),
              if (widget.habits.length > 1)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (deleting) {
                      Navigator.of(context).pop(_SheetResult.delete(h.id));
                    } else {
                      setState(() => _pendingDelete = h.id);
                    }
                  },
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: deleting
                          ? const Text(
                              '删除',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE53935),
                              ),
                            )
                          : const Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: Color(0xFFD2D2D2),
                            ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 44),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(const _SheetResult(_SheetAction.create)),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F3F3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 17,
                  color: Color(0xFF8A8A8A),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '新建项目',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6E6E6E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  记事页
// =============================================================================
class NotePage extends StatefulWidget {
  const NotePage({super.key, required this.habit, required this.date});

  final Habit habit;
  final DateTime date;

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  static const List<String> _week = ['一', '二', '三', '四', '五', '六', '日'];

  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    final exist = widget.habit.notes[AppStore.key(widget.date)] ?? '';
    _controller = TextEditingController(text: exist)
      ..selection = TextSelection.collapsed(offset: exist.length);
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    AppStore.instance.saveNote(widget.habit, widget.date, _controller.text);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.date;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 17,
                        color: _ink,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      foregroundColor: _ink,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${d.year}年${d.month}月${d.day}日 · 周${_week[d.weekday - 1]}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFAEAEAE),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.habit.name,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  cursorColor: _ink,
                  cursorWidth: 1.6,
                  style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.75,
                    color: _ink,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: '写点什么…',
                    hintStyle: TextStyle(
                      fontSize: 16.5,
                      color: Color(0xFFC9C9C9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
