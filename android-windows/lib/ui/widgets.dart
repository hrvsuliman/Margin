import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import '../data/store.dart';
import '../sync/sync_client.dart';
import 'theme.dart';

/// The app's data and sync, set up once in main().
abstract final class Services {
  static late Store store;
  static late SyncClient sync;
}

Store get store => Services.store;

/// Rebuilds whenever data changes.
class StoreBuilder extends StatelessWidget {
  const StoreBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, Store store) builder;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Services.store, builder: (context, _) => builder(context, Services.store));
}

/// Serif section header with an optional trailing note.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(text, style: context.serifTitle.copyWith(fontSize: 19))),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// A sheet-coloured group of rows, like an inset grouped list on the iPhone.
class Group extends StatelessWidget {
  const Group({super.key, required this.children, this.padding = EdgeInsets.zero});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(indent: 16));
      rows.add(children[i]);
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
    );
  }
}

/// A calm message for screens or sections without content.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: context.colors.faintInk),
            const SizedBox(height: 10),
            Text(title, style: context.serifTitle, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.colors.secondaryInk)),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      );
}

class SubjectDot extends StatelessWidget {
  const SubjectDot(this.colorKey, {super.key, this.size = 10});
  final String? colorKey;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: subjectColor(context, colorKey), shape: BoxShape.circle),
      );
}

/// Content width limit so lists don't stretch across a wide PC window.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 760, this.padding});
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => ListView(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      );
}

/// Progress ring for exam readiness.
class ReadinessRing extends StatelessWidget {
  const ReadinessRing({super.key, required this.value, this.size = 58});
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0.0, 1.0).toDouble(), context.colors.ruling, context.colors.ink),
          child: Center(
            child: Text('${(value * 100).round()} %', style: TextStyle(fontSize: size * 0.22, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.track, this.fill);
  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, paint..color = fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.fill != fill || old.track != track;
}

Future<bool> confirm(BuildContext context, String title, {String? message, String action = 'Löschen'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: context.colors.marginRed),
          child: Text(action),
        ),
      ],
    ),
  );
  return result == true;
}

Future<String?> askText(BuildContext context, String title, {String initial = '', String? hint, String action = 'OK'}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(action)),
      ],
    ),
  );
}

Future<DateTime?> pickDay(BuildContext context, DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('de'),
    );

Future<TimeOfDay?> pickTime(BuildContext context, DateTime? initial) => showTimePicker(
      context: context,
      initialTime: initial == null ? const TimeOfDay(hour: 8, minute: 0) : TimeOfDay.fromDateTime(initial),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

/// Subject picker used by all editors.
class SubjectField extends StatelessWidget {
  const SubjectField({super.key, required this.value, required this.onChanged, this.label = 'Fach'});
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final subjects = store.subjects;
    final known = subjects.any((s) => s.uid == value);
    return DropdownButtonFormField<String?>(
      initialValue: known ? value : null,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Kein Fach')),
        for (final s in subjects)
          DropdownMenuItem<String?>(
            value: s.uid,
            child: Row(children: [SubjectDot(s.colorKey), const SizedBox(width: 10), Text(s.name)]),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// "Fällig Morgen", "Überfällig seit Gestern" …
String dueLabel(Task task) {
  final due = task.dueDate;
  if (due == null) return '';
  final day = Fmt.relativeDay(due);
  final time = task.hasDueTime ? ', ${Fmt.time(due)}' : '';
  return task.isOverdue() ? 'Überfällig · $day$time' : '$day$time';
}

/// Wide layouts (tablet, PC) get side-by-side panes.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 760;
