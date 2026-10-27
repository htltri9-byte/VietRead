import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/genre.dart';
import 'package:vietread/models/import_job.dart';
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

  // ---------------- Thêm chương vào truyện đã có (A3.11) ------------------

  group('importChapterFromUrl / importChapterFromText (mock)', () {
    setUp(MockApiService.resetStoriesForTest);

    const String link = 'https://m.qidian.com/chapter/1040765595/806596284/';

    Future<MockApiService> ownerApi() async {
      final MockApiService mock = api();
      await mock.login('tacgia@vietread.vn', 'VietRead@123');
      return mock;
    }

    test(
      'thêm link thành công → max+1, chống trùng 409, đúng host www/m',
      () async {
        final MockApiService mock = await ownerApi();

        final Chapter ch = await mock.importChapterFromUrl(1, chapterUrl: link);
        expect(ch.index, 129); // truyện 1 có 128 chương → MAX+1
        expect(ch.storyId, 1);
        expect(ch.content, contains('Qidian'));
        expect(await mock.fetchChapters(1, pageSize: 200), hasLength(129));

        // Dán lại cùng chương (bản www — khác host, cùng chapterId) → 409
        expect(
          mock.importChapterFromUrl(
            1,
            chapterUrl: 'https://www.qidian.com/chapter/1040765595/806596284/',
          ),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 409)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  contains('Chương này đã được nhập'),
                ),
          ),
        );
      },
    );

    test(
      'link thuộc truyện khác / không phải Qidian / lỗi nguồn VIP',
      () async {
        final MockApiService mock = await ownerApi();
        await mock.importChapterFromUrl(1, chapterUrl: link); // ghi bookId

        // BookId khác → chống nhầm truyện
        expect(
          mock.importChapterFromUrl(
            1,
            chapterUrl: 'https://m.qidian.com/chapter/1035420986/806596284/',
          ),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.statusCode, 'statusCode', 400)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Link này thuộc truyện khác',
                ),
          ),
        );

        // Domain khác → 400
        expect(
          mock.importChapterFromUrl(1, chapterUrl: 'https://example.com/x/1'),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.message,
              'message',
              'Chỉ hỗ trợ thêm chương từ Qidian',
            ),
          ),
        );

        // Giả lập lỗi nguồn (chương VIP) — không vượt rào
        expect(
          mock.importChapterFromUrl(
            1,
            chapterUrl: 'https://m.qidian.com/chapter/1040765595/vip/',
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.message,
              'message',
              contains('VIP'),
            ),
          ),
        );
      },
    );

    test('không phải chủ truyện → 403', () async {
      final MockApiService mock = api();
      await mock.login('docgia@vietread.vn', 'VietRead@123');
      expect(
        mock.importChapterFromUrl(1, chapterUrl: link),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });

    test(
      'import-text: vi lưu nguyên, zh mô phỏng dịch, tự đánh số + 409',
      () async {
        final MockApiService mock = await ownerApi();

        final Chapter vi = await mock.importChapterFromText(
          1,
          text: 'Nội dung tiếng Việt giữ nguyên.',
          sourceLang: 'vi',
        );
        expect(vi.index, 129);
        expect(vi.content, 'Nội dung tiếng Việt giữ nguyên.');

        final Chapter zh = await mock.importChapterFromText(
          1,
          text: '第一章\nNội dung tiếng Trung.',
          sourceLang: 'zh',
        );
        expect(zh.index, 130); // MAX+1 sau chương 129
        expect(zh.content, startsWith('Bản dịch'));

        // chapterNo được ưu tiên; gửi lại số đã có → 409
        final Chapter ten = await mock.importChapterFromText(
          1,
          text: 'Chương số 200.',
          sourceLang: 'vi',
          chapterNo: 200,
        );
        expect(ten.index, 200);
        expect(
          mock.importChapterFromText(
            1,
            text: 'Trùng số.',
            sourceLang: 'vi',
            chapterNo: 200,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.statusCode,
              'statusCode',
              409,
            ),
          ),
        );

        // sourceLang sai → 400
        expect(
          mock.importChapterFromText(1, text: 'abc', sourceLang: 'fr'),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.statusCode,
              'statusCode',
              400,
            ),
          ),
        );
      },
    );
  });

  // ---------- Tác giả nguyên tác vs Người đăng (tách bạch 2 khái niệm) ----------

  group('originalAuthor / uploaderName (mock)', () {
    setUp(MockApiService.resetStoriesForTest);

    test('seed đủ 2 trường mới; author tương thích = originalAuthor', () async {
      final List<Story> stories = await api().fetchStories(pageSize: 100);
      final Story s = stories.firstWhere((Story s) => s.id == 1);
      expect(s.originalAuthor, 'Trần Nhật Nam');
      expect(s.uploaderName, 'Trần Nhật Nam');
      expect(s.author, 'Trần Nhật Nam');
    });

    test('truyện nhập mock có tác giả gốc từ nguồn (demo fixture)', () async {
      final MockApiService mock = api();
      await mock.login('tacgia@vietread.vn', 'VietRead@123');
      final int jobId = await mock.startImport(
        sourceUrl: 'https://demo.vietread.local/book/1',
      );
      ImportJob job = await mock.fetchImportJob(jobId);
      for (int i = 0; i < 4 && job.status != 'Done' && job.status != 'Failed'; i++) {
        await Future<void>.delayed(Duration.zero);
        job = await mock.fetchImportJob(jobId);
      }
      expect(job.status, 'Done');
      final Story imported = await mock.fetchStory(job.storyId!);
      expect(imported.originalAuthor, 'Diễn Kì Tác Người');
      // Người đăng = tài khoản vừa import (mock: tên lấy trước @).
      expect(imported.uploaderName, 'tacgia');
    });

    test('tìm theo originalAuthor khác tên người đăng + vẫn tìm theo người đăng',
        () async {
      final MockApiService mock = api();
      await mock.login('tacgia@vietread.vn', 'VietRead@123');
      final Story created = await mock.createStory(
        title: 'Truyện Có Tác Giả',
        originalAuthor: 'Hàn Mặc Kiếm',
      );
      // Truyện mới tạo là nháp → CHƯA xuất hiện ở tìm kiếm công khai.
      expect(await mock.fetchStories(query: 'Hàn Mặc Kiếm'), isEmpty);
      // Sau khi Admin duyệt (mock: đặt trạng thái) thì tìm thấy.
      MockApiService.setModerationForTest(created.id, 'approved');

      final List<Story> byAuthor = await mock.fetchStories(query: 'Hàn Mặc Kiếm');
      expect(byAuthor, hasLength(1));
      // Không mất kết quả cũ theo tên người đăng (seed).
      expect(await mock.fetchStories(query: 'Lâm Gia Huy'), hasLength(2));
    });

    test('createStory: originalAuthor trim khi có, rỗng → null', () async {
      final MockApiService mock = api();
      await mock.login('tacgia@vietread.vn', 'VietRead@123');

      final Story a = await mock.createStory(
        title: 'Có Tác Giả',
        originalAuthor: '  Băng Tụy Trà  ',
      );
      expect(a.originalAuthor, 'Băng Tụy Trà');
      expect(a.uploaderName, 'tacgia'); // người đăng = mình
      expect(a.author, 'Băng Tụy Trà'); // trường tương thích

      final Story b = await mock.createStory(
        title: 'Không Tác Giả',
        originalAuthor: '   ',
      );
      expect(b.originalAuthor, isNull);
      expect(b.author, 'tacgia'); // fallback = người đăng
    });

    test('updateStory: đổi / xoá (rỗng) / không gửi thì giữ nguyên', () async {
      final MockApiService mock = api();
      await mock.login('tacgia@vietread.vn', 'VietRead@123');
      final Story s = await mock.createStory(
        title: 'Sửa Tác Giả',
        originalAuthor: 'A',
      );

      final Story updated = await mock.updateStory(s.id, originalAuthor: '  B  ');
      expect(updated.originalAuthor, 'B');

      final Story cleared = await mock.updateStory(s.id, originalAuthor: '');
      expect(cleared.originalAuthor, isNull);

      await mock.updateStory(s.id, originalAuthor: 'C');
      final Story unchanged = await mock.updateStory(s.id, title: 'Đổi Tên');
      expect(unchanged.originalAuthor, 'C'); // không gửi key → giữ nguyên
    });
  });
}
