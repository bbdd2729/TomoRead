import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/sync_merge_service.dart';
import 'package:tomoread/domain/models/sync_models.dart';

void main() {
  const service = SyncMergeService();
  final timestamp = DateTime.utc(2026, 8, 2, 12);

  SyncEnvelope upsert({
    required SyncEntityType type,
    required String device,
    required Map<String, Object?> payload,
    int revision = 2,
    DateTime? updatedAt,
  }) => service.createUpsert(
    entityType: type,
    entityId: 'entity-a',
    revision: revision,
    updatedAt: updatedAt ?? timestamp,
    deviceId: device,
    payload: payload,
  );

  test('uses UTC time and device id as a deterministic scalar tie-break', () {
    final left = upsert(
      type: SyncEntityType.bookmark,
      device: 'device-a',
      payload: const {'label': 'left'},
    );
    final right = upsert(
      type: SyncEntityType.bookmark,
      device: 'device-b',
      payload: const {'label': 'right'},
    );

    final leftFirst = service.merge(left, right);
    final rightFirst = service.merge(right, left);

    expect(leftFirst.envelope.payload['label'], 'right');
    expect(rightFirst.envelope.payload['label'], 'right');
  });

  test('merges stable list elements without duplicating ids', () {
    final left = upsert(
      type: SyncEntityType.bookMetadata,
      device: 'device-a',
      payload: const {
        'title': 'Book',
        'tags': [
          {'id': 'tag-a', 'label': 'A'},
        ],
      },
    );
    final right = upsert(
      type: SyncEntityType.bookMetadata,
      device: 'device-b',
      payload: const {
        'title': 'Book',
        'tags': [
          {'id': 'tag-b', 'label': 'B'},
        ],
      },
    );

    final outcome = service.merge(left, right);

    expect(outcome.envelope.revision, 3);
    expect(outcome.envelope.payload['tags'], hasLength(2));
  });

  test('preserves concurrent long text as an explicit conflict', () {
    final left = upsert(
      type: SyncEntityType.annotation,
      device: 'device-a',
      payload: const {'note': 'left note'},
    );
    final right = upsert(
      type: SyncEntityType.annotation,
      device: 'device-b',
      payload: const {'note': 'right note'},
    );

    final outcome = service.merge(left, right);

    expect(outcome.disposition, SyncMergeDisposition.conflict);
    expect(outcome.conflict?.fieldNames, ['note']);
    expect(outcome.envelope.payload['note'], 'left note');
  });

  test('a tombstone wins a same-revision update and blocks older data', () {
    final current = upsert(
      type: SyncEntityType.bookmark,
      device: 'device-a',
      payload: const {'label': 'current'},
      revision: 3,
    );
    final tombstone = service.createDelete(
      entityType: SyncEntityType.bookmark,
      entityId: 'entity-a',
      revision: 3,
      deletedAt: timestamp,
      deviceId: 'device-b',
    );

    final deleted = service.merge(current, tombstone).envelope;
    final stale = upsert(
      type: SyncEntityType.bookmark,
      device: 'device-c',
      payload: const {'label': 'stale'},
      revision: 2,
    );

    expect(deleted.isDeleted, isTrue);
    expect(service.merge(deleted, stale).envelope.isDeleted, isTrue);
  });

  test('rejects payloads containing credentials or complete source text', () {
    expect(
      () => upsert(
        type: SyncEntityType.readingSettings,
        device: 'device-a',
        payload: const {'api_key': 'secret'},
      ),
      throwsFormatException,
    );
    expect(
      () => upsert(
        type: SyncEntityType.bookMetadata,
        device: 'device-a',
        payload: const {'rawText': 'whole book'},
      ),
      throwsFormatException,
    );
    expect(
      () => upsert(
        type: SyncEntityType.readingSettings,
        device: 'device-a',
        payload: const {
          'provider': {'access_token': 'secret'},
        },
      ),
      throwsFormatException,
    );
  });
}
