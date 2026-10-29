import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/features/scan/auto_return_cubit.dart';

void main() {
  late StreamController<void> clock;
  late int listeners;
  late AutoReturnCubit cubit;

  setUp(() {
    listeners = 0;
    clock = StreamController<void>.broadcast(
      onListen: () => listeners++,
      onCancel: () => listeners--,
    );
    cubit = AutoReturnCubit(ticker: () => clock.stream);
  });

  tearDown(() async {
    await cubit.close();
    await clock.close();
  });

  Future<void> tick([int times = 1]) async {
    for (var i = 0; i < times; i++) {
      clock.add(null);
      await pumpEventQueue();
    }
  }

  test('is idle until a send succeeded', () {
    expect(cubit.state.phase, AutoReturnPhase.idle);
    expect(listeners, 0);
  });

  test('counts down once a second from the constant', () async {
    expect(autoReturnSeconds, 10);
    cubit.start();
    expect(cubit.state.remaining, 10);

    await tick(3);

    expect(cubit.state.phase, AutoReturnPhase.counting);
    expect(cubit.state.remaining, 7);
  });

  test('reaches zero once and stops listening to the clock', () async {
    final phases = <AutoReturnPhase>[];
    cubit.stream.listen((s) => phases.add(s.phase));
    cubit.start();

    await tick(autoReturnSeconds + 3);

    expect(cubit.state.phase, AutoReturnPhase.due);
    expect(phases.where((p) => p == AutoReturnPhase.due), hasLength(1));
    expect(listeners, 0);
  });

  test('a touch stops it for good', () async {
    cubit.start();
    await tick(2);

    cubit.stop();
    await tick(20);

    expect(cubit.state.phase, AutoReturnPhase.stopped);
    expect(listeners, 0);
  });

  test('a second start does not restart the count', () async {
    cubit.start();
    await tick(4);

    cubit.start();

    expect(cubit.state.remaining, 6);
    expect(listeners, 1);
  });

  test('stop after due or before start does nothing', () async {
    cubit.stop();
    expect(cubit.state.phase, AutoReturnPhase.idle);
    cubit.start();
    await tick(autoReturnSeconds);
    cubit.stop();
    expect(cubit.state.phase, AutoReturnPhase.due);
  });

  test('closing ends the count: no tick arrives afterwards', () async {
    cubit.start();
    await tick(2);

    await cubit.close();
    await tick(20);

    expect(cubit.state.phase, AutoReturnPhase.counting);
    expect(listeners, 0);
  });
}
