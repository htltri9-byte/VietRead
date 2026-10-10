import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/genre.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/services/api_config.dart';
import 'package:vietread/services/api_service.dart';
import 'package:vietread/services/mock_api_service.dart';

/// Kiểm tra `MockApiService` lọc / sắp xếp / phân trang **giống hệt backend**
/// (GET /stories?query=&genre=&status=&sort=&page=&pageSize=).
void main() {
  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  test('fetchGenres trả đủ thể loại mẫu', () async {
    final List<Genre> genres = await api().fetchGenres();
    expect(genres.length, greaterThanOrEqualTo(8));
    expect(genres.map((Genre g) => g.name), contains('Tiên Hiệp'));
  });

  test('mặc định sắp xếp mới nhất trước, đủ 8 truyện', () async {
    final List<Story> stories = await api().fetchStories(pageSize: 100);
    expect(stories, hasLength(8));

    for (int i = 1; i < stories.length; i++) {
      expect(
        stories[i - 1].updatedAt.isAfter(stories[i].updatedAt),
        isTrue,
        reason: 'sort=newest phải giảm dần theo updatedAt',
      );
    }
  });

  test('sort=rating: điểm giảm dần', () async {
    final List<Story> stories = await api().fetchStories(
      sort: 'rating',
      pageSize: 100,
    );
    expect(stories.first.rating, 4.8); // Hoàng Đạo Chi Tâm
    for (int i = 1; i < stories.length; i++) {
      expect(stories[i - 1].rating >= stories[i].rating, isTrue);
    }
  });

  test('lọc theo thể loại / trạng thái / truy vấn', () async {
    final List<Story> byGenre = await api().fetchStories(genre: 'Trinh Thám');
    expect(byGenre, isNotEmpty);
    expect(byGenre.every((Story s) => s.genres.contains('Trinh Thám')), isTrue);

    final List<Story> completed = await api().fetchStories(status: 'completed');
    expect(completed, isNotEmpty);
    expect(completed.every((Story s) => s.isCompleted), isTrue);

    // query theo tên truyện
    expect(await api().fetchStories(query: 'Hoàng Đạo'), hasLength(1));
    // query theo tên tác giả
    expect(await api().fetchStories(query: 'Lâm Gia Huy'), hasLength(2));
  });

  test('phân trang: 2 trang liên tiếp không trùng sách', () async {
    final List<Story> page1 = await api().fetchStories(page: 1, pageSize: 3);
    final List<Story> page2 = await api().fetchStories(page: 2, pageSize: 3);
    final List<Story> page9 = await api().fetchStories(page: 9, pageSize: 3);

    expect(page1, hasLength(3));
    expect(page2, hasLength(3));
    expect(page9, isEmpty); // vượt dữ liệu → rỗng như backend

    final Set<int> ids1 = page1.map((Story s) => s.id).toSet();
    final Set<int> ids2 = page2.map((Story s) => s.id).toSet();
    expect(ids1.intersection(ids2), isEmpty);
  });

  test('fetchStory: có và không có truyện (Bước 5)', () async {
    final Story story = await api().fetchStory(1);
    expect(story.id, 1);
    expect(story.title, 'Kiếm Sư Vọng Tường');
    expect(story.description, isNotEmpty);

    expect(api().fetchStory(9999), throwsA(isA<ApiException>()));
  });

  test('fetchChapters: đủ số chương + phân trang (Bước 5)', () async {
    final List<ChapterSummary> page1 = await api().fetchChapters(
      1,
      page: 1,
      pageSize: 50,
    );
    expect(page1, hasLength(50));
    expect(page1.first.index, 1);
    expect(page1.first.storyId, 1);
    expect(page1.first.title, startsWith('Chương 1:'));

    final List<ChapterSummary> page3 = await api().fetchChapters(
      1,
      page: 3,
      pageSize: 50,
    );
    expect(page3.first.index, 101); // truyện id 1 có 128 chương

    final List<ChapterSummary> empty = await api().fetchChapters(
      1,
      page: 9,
      pageSize: 50,
    );
    expect(empty, isEmpty);
  });

  test('fetchChapter: nội dung đầy đủ và khớp id (Bước 5)', () async {
    final int id = MockApiService.chapterIdOf(1, 3);
    final Chapter chapter = await api().fetchChapter(id);

    expect(chapter.id, id);
    expect(chapter.storyId, 1);
    expect(chapter.index, 3);
    expect(chapter.title, startsWith('Chương 3:'));
    expect(chapter.content, contains('Chương 3'));
    expect(chapter.content, contains('MockApiService'));
    // Trả đúng cả khi id sai → lỗi tiếng Việt
    expect(api().fetchChapter(199999), throwsA(isA<ApiException>()));
  });

  test('cấu hình useMock = false (Bước 6 đã chuyển sang API thật)', () {
    expect(ApiConfig.useMock, isFalse);
    // ApiService() trả về bản HTTP khi tắt cờ mock
    expect(ApiService(), isA<HttpApiService>());
    // Đổi lại cờ là dùng mock mà không phải sửa code nơi khác
    expect(MockApiService(), isA<MockApiService>());
  });
}
