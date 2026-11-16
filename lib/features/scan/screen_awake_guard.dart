import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ports/screen_awake.dart';

/// Keeps the screen on while [busy] is true (A1-004) and gives it back in every
/// other case, including when this widget leaves the tree (the screen is left,
/// the route is replaced, the app is closed): `dispose` always switches it off.
/// Needs a `RepositoryProvider<ScreenAwake>` above it.
class ScreenAwakeGuard extends StatefulWidget {
  const ScreenAwakeGuard({super.key, required this.busy, required this.child});

  final bool busy;
  final Widget child;

  @override
  State<ScreenAwakeGuard> createState() => _ScreenAwakeGuardState();
}

class _ScreenAwakeGuardState extends State<ScreenAwakeGuard> {
  late final ScreenAwake _awake;
  var _on = false;

  @override
  void initState() {
    super.initState();
    _awake = context.read<ScreenAwake>();
    _apply(widget.busy);
  }

  @override
  void didUpdateWidget(ScreenAwakeGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _apply(widget.busy);
  }

  @override
  void dispose() {
    _apply(false);
    super.dispose();
  }

  void _apply(bool on) {
    if (on == _on) return;
    _on = on;
    unawaited(_awake.keepOn(on));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
