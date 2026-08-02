import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/sync_repository.dart';
import 'package:tomoread/data/services/sync_merge_service.dart';
import 'package:tomoread/domain/models/sync_models.dart';

void main() {
  late AppDatabase leftDatabase;
  late AppDatabase rightDatabase;
  late SyncRepository left;
  late SyncRepository right;
  final baseTime = DateTime.utc(2026, 8, 2, 10);

  setUp(() async {
    leftDatabase = AppDatabase.inMemory();
    rightDatabase = AppDatabase.inMemory();
    left = SyncRepository(leftDatabase);
    right = SyncRepository(rightDatabase);
    await left.registerDevice(
      deviceId: 'device-a',
      displayName: 'Left',
      now: baseTime,
    );
    await left.registerDevice(
      deviceId: 'device-b',
      displayName: 'Right',
      now: baseTime,
    );
    await right.registerDevice(
      deviceId: 'device-a',
      displayName: 'Left',
      now: baseTime,
    );
    await right.registerDevice(
      deviceId: 'device-b',
      displayName: 'Right',
      now: baseTime,
    );
  });

  tearDown(() async {
    await leftDatabase.close();
    await rightDatabase.close();
  });

  test('independent memory databases converge after concurrent scalar edits', () async {
    final seed = await left.putLocal(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      payload: const {'label': 'seed'},
      deviceId: 'device-a',
      updatedAt: baseTime,
    );
    expect(await right.find(SyncEntityType.bookmark, 'bookmark-a'), isNull);
    await right.mergeIncoming(seed);

    final leftEdit = await left.putLocal(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      payload: const {'label': 'left'},
      deviceId: 'device-a',
      updatedAt: baseTime.add(const Duration(minutes: 1)),
    );
    final rightEdit = await right.putLocal(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      payload: const {'label': 'right'},
      deviceId: 'device-b',
      updatedAt: baseTime.add(const Duration(minutes: 2)),
    );

    await left.mergeIncoming(rightEdit);
    await right.mergeIncoming(leftEdit);

    expect(
      (await left.find(SyncEntityType.bookmark, 'bookmark-a'))?.payload['label'],
      'right',
    );
    expect(
      (await right.find(SyncEntityType.bookmark, 'bookmark-a'))?.payload['label'],
      'right',
    );
  });

  test('a replicated tombstone prevents an old snapshot from resurrecting data', () async {
    final seed = await left.putLocal(
      entityType: SyncEntityType.annotation,
      entityId: 'annotation-a',
      payload: const {'note': 'seed'},
      deviceId: 'device-a',
      updatedAt: baseTime,
    );
    await right.mergeIncoming(seed);
    final tombstone = await left.deleteLocal(
      entityType: SyncEntityType.annotation,
      entityId: 'annotation-a',
      deviceId: 'device-a',
      deletedAt: baseTime.add(const Duration(minutes: 1)),
    );

    await right.mergeIncoming(tombstone);
    await left.mergeIncoming(seed);
    await right.mergeIncoming(seed);

    expect(
      (await left.find(SyncEntityType.annotation, 'annotation-a'))?.isDeleted,
      isTrue,
    );
    expect(
      (await right.find(SyncEntityType.annotation, 'annotation-a'))?.isDeleted,
      isTrue,
    );
  });

  test('concurrent note edits remain pending until explicitly resolved', () async {
    final seed = await left.putLocal(
      entityType: SyncEntityType.annotation,
      entityId: 'annotation-a',
      payload: const {'note': 'seed'},
      deviceId: 'device-a',
      updatedAt: baseTime,
    );
    await right.mergeIncoming(seed);
    final leftEdit = await left.putLocal(
      entityType: SyncEntityType.annotation,
      entityId: 'annotation-a',
      payload: const {'note': 'left'},
      deviceId: 'device-a',
      updatedAt: baseTime.add(const Duration(minutes: 1)),
    );
    final rightEdit = await right.putLocal(
      entityType: SyncEntityType.annotation,
      entityId: 'annotation-a',
      payload: const {'note': 'right'},
      deviceId: 'device-b',
      updatedAt: baseTime.add(const Duration(minutes: 1)),
    );

    await left.mergeIncoming(rightEdit);
    await right.mergeIncoming(leftEdit);
    final conflicts = await left.pendingConflicts();
    expect(conflicts, hasLength(1));

    final resolved = await left.resolveConflict(
      conflictId: conflicts.single.id,
      resolutionPayload: const {'note': 'merged manually'},
      deviceId: 'device-a',
      resolvedAt: baseTime.add(const Duration(minutes: 3)),
    );
    await right.mergeIncoming(resolved);

    expect(
      (await right.find(SyncEntityType.annotation, 'annotation-a'))
          ?.payload['note'],
      'merged manually',
    );
  });

  test('purges tombstones only after all known devices acknowledge them', () async {
    await left.putLocal(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      payload: const {'label': 'seed'},
      deviceId: 'device-a',
      updatedAt: baseTime,
    );
    await left.deleteLocal(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      deviceId: 'device-a',
      deletedAt: baseTime.add(const Duration(minutes: 1)),
    );

    expect(
      await left.purgeEligibleTombstones(now: baseTime.add(const Duration(days: 1))),
      0,
    );
    await left.acknowledgeTombstone(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      deviceId: 'device-b',
    );
    expect(
      await left.purgeEligibleTombstones(now: baseTime.add(const Duration(days: 1))),
      1,
    );
  });

  test('keeps acknowledgements when the same tombstone is merged again', () async {
    await left.putLocal(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      payload: const {'label': 'seed'},
      deviceId: 'device-a',
      updatedAt: baseTime,
    );
    final tombstone = await left.deleteLocal(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      deviceId: 'device-a',
      deletedAt: baseTime.add(const Duration(minutes: 1)),
    );
    await left.acknowledgeTombstone(
      entityType: SyncEntityType.bookmark,
      entityId: 'bookmark-a',
      deviceId: 'device-b',
    );

    final replicatedTombstone = const SyncMergeService().createDelete(
      entityType: tombstone.entityType,
      entityId: tombstone.entityId,
      revision: tombstone.revision,
      deletedAt: tombstone.updatedAt,
      deviceId: 'device-b',
    );
    await left.mergeIncoming(replicatedTombstone);

    expect(
      await left.purgeEligibleTombstones(
        now: baseTime.add(const Duration(days: 1)),
      ),
      1,
    );
  });
}
