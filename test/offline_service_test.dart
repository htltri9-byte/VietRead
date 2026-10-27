import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/services/api_service.dart';
import 'package:vietread/services/db_helper.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/services/offline_service.dart';

import 'helpers/sqflite_test_setup.dart';

void main() {
  setUpAll(setUpSqfliteFfi);
  setUp(resetDbForTest);
  tearDown(() => DbHelper.instance.close());

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  OfflineService service() => OfflineService(api: api());

  test('tải toàn bộ chương vào SQLite và báo tiến trình', () async {
    final Story story = await api().fetchStory(3); // mock: 54 chương
    final List<int> ticks = <int>[];

    final int done = await service().downloadStory(
      story,
      onProgress: (int d, int total) => ticks.add(d),
    );

    expect(done, story.chapterCount);
    expect(await service().isDownloaded(story.id), isTrue);
    expect(await service().chapterCount(story.id), story.chapterCount);
    expect(ticks.first, 0); // báo tiến trình từ 0
    expect(ticks.last, story.chapterCount); // kết thúc = tổng số
    expect(await service().downloadedChapters(story.id), hasLength(done));
  });

  test('tải một khoảng chương', () async {
    final Story story = await api().fetchStory(3);
    final int done = await service().downloadStory(story, from: 5, to: 8);

    expect(done, 4);
    final DbHelper db = DbHelper.instance;
    expect(await db.hasChapter(story.id, 5), isTrue);
    expect(await db.hasChapter(story.id, 8), isTrue);
    expect(await db.hasChapter(story.id, 4), isFalse);
    expect(await db.hasChapter(story.id, 9), isFalse);
  });

  test('huỷ giữa chừng thì dừng đúng số chương đã tải', () async {
    final Story story = await api().fetchStory(3);
    int lastDone = 0;

    final int done = await service().downloadStory(
      story,
      onProgress: (int d, int total) => lastDone = d,
      isCancelled: () => lastDone >= 3, // huỷ sau khi tải được 3 chương
    );

    expect(done, 3);
    expect(await service().chapterCount(story.id), 3);
  });

  test('xoá bản tải để giải phóng bộ nhớ', () async {
    final Story story = await api().fetchStory(3);
    await service().downloadStory(story, from: 1, to: 2);

    await service().removeStory(story.id);
    expect(await service().isDownloaded(story.id), isFalse);
    expect(await service().chapterCount(story.id), 0);
    expect(await service().downloadedStories(), isEmpty);
  });

  test('truyện không tồn tại → lỗi tiếng Việt từ mock/backend', () async {
    final Story story = Story(
      id: 999,
      title: 'Không tồn tại',
      author: '?',
      authorId: 1,
      updatedAt: DateTime(2026),
    );
    await expectLater(
      service().downloadStory(story),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.message,
          'message',
          contains('Không tìm thấy truyện'),
        ),
      ),
    );
  });
}
