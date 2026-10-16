// SemanticsData.hasFlag is deprecated in favour of flagsCollection, whose
// shape is still changing between Flutter releases; hasFlag works on all of them.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/strings.dart';
import '../services/announcer.dart';
import '../services/command_center.dart';

/// A built-in screen reader for users who do not run TalkBack: it reads the
/// app's own semantics tree, so every label written for TalkBack works here.
///
///   touch          say what is under the finger (and focus it)
///   double tap     activate the focused item
///   swipe left/right   previous / next item
///   swipe up/down  adjust a slider, otherwise scroll
///   press and hold voice command
///
/// It steps aside while TalkBack or VoiceOver is on.
class VoiceGuide extends StatefulWidget {
  final bool enabled;
  final Announcer announcer;
  final S Function() strings;

  /// Turns the guide off. Called from the "Voice Guide" chip, which takes
  /// normal taps so a sighted helper can always switch it off.
  final VoidCallback onDisable;
  final Widget child;
  const VoiceGuide({
    super.key,
    required this.enabled,
    required this.announcer,
    required this.strings,
    required this.onDisable,
    required this.child,
  });

  @override
  State<VoiceGuide> createState() => _VoiceGuideState();
}

class _VoiceGuideState extends State<VoiceGuide> {
  SemanticsHandle? _handle;
  int? _focusId;
  Rect? _focusRect;
  Offset? _downAt;

  bool get _active => widget.enabled && !MediaQuery.accessibleNavigationOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHandle();
  }

  @override
  void didUpdateWidget(VoiceGuide old) {
    super.didUpdateWidget(old);
    _syncHandle();
    if (old.enabled && !widget.enabled) _focusRect = null;
  }

  void _syncHandle() {
    if (_active) {
      _handle ??= SemanticsBinding.instance.ensureSemantics();
    } else {
      _handle?.dispose();
      _handle = null;
    }
  }

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- tree

  SemanticsOwner? get _owner {
    for (final v in WidgetsBinding.instance.renderViews) {
      final o = v.owner?.semanticsOwner;
      if (o != null) return o;
    }
    return null;
  }

  double get _dpr => View.of(context).devicePixelRatio;

  /// Focusable nodes in reading order, with their rects in logical pixels.
  List<(SemanticsNode, Rect)> _nodes() {
    final root = _owner?.rootSemanticsNode;
    if (root == null) return const [];
    final out = <(SemanticsNode, Rect)>[];
    void visit(SemanticsNode n, Matrix4 parent) {
      final m = n.transform == null ? parent : (parent.clone()..multiply(n.transform!));
      final d = n.getSemanticsData();
      if (d.hasFlag(SemanticsFlag.isHidden) || n.isInvisible) return;
      final rect = MatrixUtils.transformRect(m, n.rect);
      final readable = d.label.isNotEmpty || d.value.isNotEmpty || d.hasAction(SemanticsAction.tap);
      if (readable && rect.width > 1 && rect.height > 1) {
        out.add((n, Rect.fromLTRB(rect.left / _dpr, rect.top / _dpr, rect.right / _dpr, rect.bottom / _dpr)));
      }
      if (n.mergeAllDescendantsIntoThisNode) return;
      n.visitChildren((c) {
        visit(c, m);
        return true;
      });
    }

    visit(root, Matrix4.identity());
    return out;
  }

  (SemanticsNode, Rect)? _at(Offset p) {
    (SemanticsNode, Rect)? best;
    for (final e in _nodes()) {
      if (!e.$2.contains(p)) continue;
      // The smallest rect under the finger is the most specific item.
      if (best == null || e.$2.width * e.$2.height <= best.$2.width * best.$2.height) best = e;
    }
    return best;
  }

  String _describe(SemanticsData d) {
    final s = widget.strings();
    final parts = <String>[
      if (d.label.isNotEmpty) d.label,
      if (d.value.isNotEmpty) d.value,
      if (d.hasFlag(SemanticsFlag.hasToggledState)) d.hasFlag(SemanticsFlag.isToggled) ? s.on : s.off,
      if (d.hasFlag(SemanticsFlag.hasCheckedState) && d.hasFlag(SemanticsFlag.isChecked)) s.selected,
      if (d.hasFlag(SemanticsFlag.isSelected)) s.selected,
      if (d.hasFlag(SemanticsFlag.isHeader)) s.heading,
      if (d.hasFlag(SemanticsFlag.hasEnabledState) && !d.hasFlag(SemanticsFlag.isEnabled)) s.disabled,
      if (d.hint.isNotEmpty) d.hint else if (d.hasAction(SemanticsAction.tap)) s.doubleTapToActivate,
    ];
    return parts.join('. ');
  }

  void _focus((SemanticsNode, Rect)? e, {bool speakEmpty = false}) {
    if (e == null) {
      setState(() => _focusRect = null);
      return;
    }
    final changed = e.$1.id != _focusId;
    setState(() {
      _focusId = e.$1.id;
      _focusRect = e.$2;
    });
    if (changed || speakEmpty) {
      widget.announcer.buzz(Buzz.light);
      widget.announcer.say(
        _describe(e.$1.getSemanticsData()),
        priority: Priority.urgent,
        dedupe: Duration.zero,
        force: true,
      );
    }
  }

  (SemanticsNode, Rect)? _focused() {
    final id = _focusId;
    if (id == null) return null;
    for (final e in _nodes()) {
      if (e.$1.id == id) return e;
    }
    return null;
  }

  // ---------------------------------------------------------------- gestures

  void _onTap() {
    final p = _downAt;
    if (p != null) _focus(_at(p), speakEmpty: true);
  }

  void _onDoubleTap() {
    final e = _focused() ?? (_downAt == null ? null : _at(_downAt!));
    if (e == null) return;
    final d = e.$1.getSemanticsData();
    final action = d.hasAction(SemanticsAction.tap)
        ? SemanticsAction.tap
        : d.hasAction(SemanticsAction.longPress)
        ? SemanticsAction.longPress
        : null;
    if (action == null) return;
    widget.announcer.buzz(Buzz.success);
    _owner?.performAction(e.$1.id, action);
    // Read the new state (switch toggled, tab selected) once the tree updates.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final again = _focused();
      if (again != null) {
        final dd = again.$1.getSemanticsData();
        if (dd.hasFlag(SemanticsFlag.hasToggledState) || dd.hasFlag(SemanticsFlag.isSelected)) {
          widget.announcer.say(_describe(dd), priority: Priority.high, dedupe: Duration.zero, force: true);
        }
        setState(() => _focusRect = again.$2);
      } else {
        setState(() => _focusRect = null);
      }
    });
  }

  void _move(int step) {
    final all = _nodes();
    if (all.isEmpty) return;
    final i = all.indexWhere((e) => e.$1.id == _focusId);
    final next = i < 0 ? (step > 0 ? 0 : all.length - 1) : i + step;
    if (next < 0 || next >= all.length) {
      final s = widget.strings();
      widget.announcer.say(next < 0 ? s.startOfScreen : s.endOfScreen, priority: Priority.high, dedupe: Duration.zero);
      return;
    }
    _focus(all[next]);
  }

  void _vertical(bool up) {
    final e = _focused();
    final owner = _owner;
    if (owner == null) return;
    if (e != null) {
      final d = e.$1.getSemanticsData();
      final adjust = up ? SemanticsAction.increase : SemanticsAction.decrease;
      if (d.hasAction(adjust)) {
        owner.performAction(e.$1.id, adjust);
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          final again = _focused();
          if (again != null && mounted) {
            widget.announcer.say(
              again.$1.getSemanticsData().value,
              priority: Priority.urgent,
              dedupe: Duration.zero,
              force: true,
            );
          }
        });
        return;
      }
    }
    // Scroll the nearest scrollable that contains the focus (or any).
    final scroll = up ? SemanticsAction.scrollUp : SemanticsAction.scrollDown;
    SemanticsNode? target;
    SemanticsNode? n = e?.$1;
    while (n != null) {
      if (n.getSemanticsData().hasAction(scroll)) {
        target = n;
        break;
      }
      n = n.parent;
    }
    if (target == null) {
      final root = owner.rootSemanticsNode;
      void find(SemanticsNode x) {
        if (target != null) return;
        if (x.getSemanticsData().hasAction(scroll)) {
          target = x;
          return;
        }
        x.visitChildren((c) {
          find(c);
          return target == null;
        });
      }

      if (root != null) find(root);
    }
    if (target != null) {
      widget.announcer.buzz(Buzz.light);
      owner.performAction(target!.id, scroll);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return widget.child;
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _downAt = d.globalPosition,
            onTap: _onTap,
            onDoubleTapDown: (d) => _downAt = d.globalPosition,
            onDoubleTap: _onDoubleTap,
            onLongPress: CommandCenter.instance.listen,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 250) _move(v > 0 ? 1 : -1);
            },
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              // Finger moving up = content up = scroll down / increase.
              if (v.abs() > 250) _vertical(v < 0);
            },
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: _GuideChip(strings: widget.strings, announcer: widget.announcer, onDisable: widget.onDisable),
          ),
        ),
        if (_focusRect != null)
          Positioned.fromRect(
            rect: _focusRect!.inflate(3),
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent, width: 3),
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 14)],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Voice Guide on" chip in the top corner. It takes ordinary taps: the first
/// tap warns (aloud and on screen), a second tap within 4 s turns the guide off.
class _GuideChip extends StatefulWidget {
  final S Function() strings;
  final Announcer announcer;
  final VoidCallback onDisable;
  const _GuideChip({required this.strings, required this.announcer, required this.onDisable});

  @override
  State<_GuideChip> createState() => _GuideChipState();
}

class _GuideChipState extends State<_GuideChip> {
  DateTime? _armed;

  bool get _isArmed => _armed != null && DateTime.now().difference(_armed!) < const Duration(seconds: 4);

  void _tap() {
    final s = widget.strings();
    if (_isArmed) {
      widget.onDisable();
      widget.announcer.say(s.voiceGuideOff, priority: Priority.urgent, dedupe: Duration.zero, force: true);
      return;
    }
    setState(() => _armed = DateTime.now());
    widget.announcer.say(
      s.t('Tap again to turn off the voice guide.', 'Gusa tena kuzima mwongozo wa sauti.'),
      priority: Priority.urgent,
      dedupe: Duration.zero,
      force: true,
    );
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings();
    final scheme = Theme.of(context).colorScheme;
    final armed = _isArmed;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: armed ? scheme.error : scheme.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                armed ? Icons.touch_app_rounded : Icons.record_voice_over_rounded,
                size: 16,
                color: armed ? scheme.onError : scheme.onPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                armed
                    ? s.t('Tap again to turn off', 'Gusa tena kuzima')
                    : s.t('Voice guide · Turn off', 'Mwongozo · Zima'),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: armed ? scheme.onError : scheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
