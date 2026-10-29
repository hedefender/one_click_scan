import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// Seconds the result screen waits after a successful send before it goes back
/// to the home screen (Phase 5.1). The one place that holds the number.
const autoReturnSeconds = 10;

enum AutoReturnPhase {
  /// Nothing to count for (the scan is not sent, or the e-mail app was opened).
  idle,
  counting,

  /// The user touched the screen: they stay as long as they like.
  stopped,

  /// The count reached zero; the screen goes home (reported once).
  due,
}

class AutoReturnState {
  const AutoReturnState({
    this.phase = AutoReturnPhase.idle,
    this.remaining = autoReturnSeconds,
  });

  final AutoReturnPhase phase;
  final int remaining;

  bool get counting => phase == AutoReturnPhase.counting;

  @override
  bool operator ==(Object other) =>
      other is AutoReturnState &&
      other.phase == phase &&
      other.remaining == remaining;

  @override
  int get hashCode => Object.hash(phase, remaining);
}

/// The countdown to the automatic return. One tick a second (no animation); the
/// ticker is injected so a test can drive time by hand. The subscription ends
/// when the count ends, when the user touches the screen and when the cubit is
/// closed, so nothing navigates after the user has left.
class AutoReturnCubit extends Cubit<AutoReturnState> {
  AutoReturnCubit({Stream<void> Function()? ticker})
    : _ticker = ticker ?? _everySecond,
      super(const AutoReturnState());

  final Stream<void> Function() _ticker;
  StreamSubscription<void>? _subscription;

  static Stream<void> _everySecond() =>
      Stream<void>.periodic(const Duration(seconds: 1));

  /// Starts the count once; later calls do nothing.
  void start() {
    if (state.phase != AutoReturnPhase.idle) return;
    emit(const AutoReturnState(phase: AutoReturnPhase.counting));
    _subscription = _ticker().listen((_) {
      final remaining = state.remaining - 1;
      if (remaining <= 0) {
        _end();
        emit(const AutoReturnState(phase: AutoReturnPhase.due, remaining: 0));
      } else {
        emit(
          AutoReturnState(
            phase: AutoReturnPhase.counting,
            remaining: remaining,
          ),
        );
      }
    });
  }

  /// Any touch on the screen.
  void stop() {
    if (state.phase != AutoReturnPhase.counting) return;
    _end();
    emit(const AutoReturnState(phase: AutoReturnPhase.stopped));
  }

  void _end() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  Future<void> close() {
    _end();
    return super.close();
  }
}
