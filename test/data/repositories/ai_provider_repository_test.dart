import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/ai_provider_repository.dart';
import 'package:tomoread/domain/models/chat_models.dart';

void main() {
  late AppDatabase database;
  late AiProviderRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = AiProviderRepository(database);
  });

  tearDown(() => database.close());

  test('stores multiple preset-backed profiles and activates explicitly', () async {
    final ollama = await repository.save(
      name: 'Local Ollama',
      presetId: 'ollama',
      authType: AiProviderAuthType.none,
      baseUrl: 'http://localhost:11434/v1',
      modelId: 'qwen3',
      secretKeyId: 'secret-ollama',
      capabilitiesJson: '{"modelList":true}',
    );
    final openAi = await repository.save(
      name: 'OpenAI work',
      presetId: 'openai',
      baseUrl: 'https://api.openai.com/v1',
      modelId: 'model-a',
      secretKeyId: 'secret-openai',
    );

    expect((await repository.listProfiles()), hasLength(2));
    expect((await repository.loadActive())?.id, openAi.id);

    await repository.activate(ollama.id);
    final active = await repository.loadActive();
    expect(active?.id, ollama.id);
    expect(active?.presetId, 'ollama');
    expect(active?.authType, AiProviderAuthType.none);
    expect(active?.capabilitiesJson, '{"modelList":true}');

    await repository.setEnabled(ollama.id, false);
    expect(await repository.loadActive(), isNull);
  });
}
