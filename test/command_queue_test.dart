import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/shortcuts/command_queue.dart';

void main() {
  test('runs tasks one at a time, in arrival order', () async {
    final q = CommandQueue();
    final log = <String>[];
    var running = 0;
    var overlapped = false;

    Future<void> task(String name, int ms) async {
      running++;
      if (running > 1) overlapped = true;
      log.add('$name+');
      await Future<void>.delayed(Duration(milliseconds: ms));
      log.add('$name-');
      running--;
    }

    // The first task is the slowest on purpose: unqueued, b and c would both
    // start and finish inside a's delay, which is exactly the interleaving that
    // lets a second capture replace the handle a is about to apply to.
    q.add(() => task('a', 30));
    q.add(() => task('b', 1));
    await q.add(() => task('c', 1));

    expect(overlapped, isFalse);
    expect(log, ['a+', 'a-', 'b+', 'b-', 'c+', 'c-']);
  });

  test('a failing task does not wedge the queue', () async {
    // A rejected tail would reject every command chained behind it, so one
    // thrown error would silently kill every shortcut for the rest of the
    // session — a worse failure than the race being fixed.
    final q = CommandQueue();
    final done = <String>[];
    await expectLater(
        q.add(() async => throw StateError('boom')), throwsStateError);
    await q.add(() async => done.add('after'));
    expect(done, ['after']);
  });

  test('the error reaches the caller, not just the queue', () async {
    final q = CommandQueue();
    await expectLater(q.add(() async => throw StateError('boom')),
        throwsStateError);
  });

  test('an idle queue starts the next task without waiting', () async {
    // The overlay summon goes through here too and is on a latency budget, so
    // an empty queue must cost no more than a microtask hop.
    final q = CommandQueue();
    var ran = false;
    final f = q.add(() async => ran = true);
    expect(ran, isFalse, reason: 'runs asynchronously, never inline');
    await f;
    expect(ran, isTrue);
  });
}
