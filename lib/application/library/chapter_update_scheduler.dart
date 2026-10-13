import 'package:cron/cron.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns chapter-update scheduling and its user preferences.
class ChapterUpdateScheduler {
  final Future<void> Function() onRun;
  final void Function() onChanged;
  final void Function(Object error)? onScheduleError;

  Duration _interval = const Duration(hours: 24);
  Set<String> _tabs = {};
  bool _enabled = true;
  Cron? _cron;

  ChapterUpdateScheduler({
    required this.onRun,
    required this.onChanged,
    this.onScheduleError,
  });

  Duration get interval => _interval;
  Set<String> get tabs => Set.unmodifiable(_tabs);
  bool get enabled => _enabled;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final hours = prefs.getInt('updateIntervalHours') ?? 24;
    _interval = Duration(hours: hours > 0 ? hours : 24);
    _tabs = (prefs.getStringList('tabsToUpdate') ?? const []).toSet();
    _enabled = prefs.getBool('trackerEnabled') ?? true;
    _schedule();
    onChanged();
  }

  Future<void> setInterval(Duration interval) async {
    if (interval.inHours <= 0) return;
    _interval = interval;
    _schedule();
    onChanged();
    await _save();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _schedule();
    onChanged();
    await _save();
  }

  Future<void> setTabs(Set<String> tabs) async {
    _tabs = Set.from(tabs);
    onChanged();
    await _save();
  }

  void dispose() {
    _cron?.close();
    _cron = null;
  }

  void _schedule() {
    _cron?.close();
    _cron = null;
    if (!_enabled) return;

    final cron = Cron();
    try {
      cron.schedule(Schedule.parse(_cronExpression(_interval)), () async {
        await onRun();
      });
      _cron = cron;
    } catch (error) {
      cron.close();
      onScheduleError?.call(error);
    }
  }

  String _cronExpression(Duration interval) {
    if (interval.inHours == 24) return '0 0 * * *';
    return '0 */${interval.inHours} * * *';
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('updateIntervalHours', _interval.inHours);
    await prefs.setStringList('tabsToUpdate', _tabs.toList());
    await prefs.setBool('trackerEnabled', _enabled);
  }
}
