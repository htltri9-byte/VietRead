import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/comment.dart';
import 'package:vietread/models/genre.dart';
import 'package:vietread/models/import_job.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/models/user.dart';

void main() {
  // JSON bên dưới được **chép nguyên văn** từ backend đang chạy
  // (GET /stories, /genres, /stories/1/chapters, /chapters/1, POST /auth/login).
  const String storyJson = '''
  {
    "id": 3,
    "title": "Hoàng Đạo Chi Tâm",
    "author": "Trần Nhật Nam",
    "authorId": 1,
    "coverUrl": null,
    "description": "Sau khi trời đất phân tách, mười hai hoàng đạo rơi xuống nhân gian.",
    "genres": ["Huyền Huyễn", "Trinh Thám"],
    "status": "ongoing",
    "rating": 4.8,
    "chapterCount": 3,
    "isDraft": false,
    "updatedAt": "2026-10-06T10:47:48.657115"
  }''';

  const String genresJson =
      '[{"id":4,"name":"Đô Thị"},{"id":2,"name":"Huyền Huyễn"}]';

  const String chapterSummaryJson = '''
  {
    "id": 1,
    "storyId": 1,
    "index": 1,
    "title": "Chương 1: Kiếm Ngưng Tường",
    "updatedAt": "2026-10-06T10:47:48.653391"
  }''';

  const String chapterJson = '''
  {
    "id": 1,
    "storyId": 1,
    "index": 1,
    "title": "Chương 1: Kiếm Ngưng Tường",
    "content": "Hồi ấy trời vừa sáng, sương còn đọng trên ngọn cỏ biên thành."
  }''';

  const String loginJson = '''
  {
    "token": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIyIn0.abc",
    "user": {"id": 2, "name": "Lê Minh Anh", "email": "docgia@vietread.vn", "avatarUrl": null}
  }''';

  const String commentJson = '''
  {
    "id": 1,
    "storyId": 1,
    "chapterId": null,
    "userId": 2,
    "userName": "Lê Minh Anh",
    "avatarUrl": null,
    "content": "Truyện đọc cuốn lắm, mong tác giả ra chương nhanh!",
    "createdAt": "2026-10-06T10:47:48.660000"
  }''';

  Map<String, dynamic> decode(String source) =>
      jsonDecode(source) as Map<String, dynamic>;

  group('Story', () {
    test('fromJson đọc đúng JSON của backend', () {
      final Story story = Story.fromJson(decode(storyJson));

      expect(story.id, 3);
      expect(story.title, 'Hoàng Đạo Chi Tâm');
      expect(story.author, 'Trần Nhật Nam');
      expect(story.authorId, 1);
      expect(story.coverUrl, isNull);
      expect(story.description, contains('hoàng đạo'));
      expect(story.genres, <String>['Huyền Huyễn', 'Trinh Thám']);
      expect(story.status, 'ongoing');
      expect(story.rating, 4.8);
      expect(story.chapterCount, 3);
      expect(story.isDraft, isFalse);
      expect(story.updatedAt.year, 2026);
    });

    test('các nhãn hiển thị tiếng Việt đúng', () {
      final Story story = Story.fromJson(decode(storyJson));

      expect(story.isCompleted, isFalse);
      expect(story.statusLabel, 'Đang ra');
      expect(story.ratingLabel, '4.8');
      expect(story.chapterLabel, '3 chương');

      final Story done = Story.fromJson(<String, dynamic>{
        'id': 1,
        'title': 'x',
        'author': 'y',
        'authorId': 1,
        'status': 'completed',
        'rating': 4.0,
        'chapterCount': 1,
        'updatedAt': story.updatedAt.toIso8601String(),
      });
      expect(done.statusLabel, 'Hoàn thành');
    });

    test('toJson → fromJson giữ nguyên dữ liệu (round-trip)', () {
      final Story story = Story.fromJson(decode(storyJson));
      final Map<String, dynamic> roundTrip = Story.fromJson(story.toJson())
          .toJson();

      expect(roundTrip, story.toJson());
      expect(roundTrip['genres'], <String>['Huyền Huyễn', 'Trinh Thám']);
      expect(roundTrip['rating'], 4.8);
    });

    test('updatedLabel tính đúng mốc thời gian (tiếng Việt)', () {
      Story withAgo(Duration ago) => Story(
        id: 1,
        title: 'x',
        author: 'y',
        authorId: 1,
        updatedAt: DateTime.now().subtract(ago),
      );

      expect(withAgo(const Duration(seconds: 5)).updatedLabel, 'Vừa xong');
      expect(
        withAgo(const Duration(minutes: 12)).updatedLabel,
        '12 phút trước',
      );
      expect(withAgo(const Duration(hours: 5)).updatedLabel, '5 giờ trước');
      expect(withAgo(const Duration(days: 3)).updatedLabel, '3 ngày trước');
    });
  });

  test('Genre.fromJson đọc { id, name }', () {
    final List<dynamic> data = jsonDecode(genresJson) as List<dynamic>;
    final List<Genre> genres = data
        .cast<Map<String, dynamic>>()
        .map(Genre.fromJson)
        .toList();

    expect(genres, hasLength(2));
    expect(genres.first.name, 'Đô Thị');
    expect(genres.last.id, 2);
    expect(genres.first.toJson(), <String, dynamic>{'id': 4, 'name': 'Đô Thị'});
  });

  test('ChapterSummary / Chapter đọc đúng JSON', () {
    final ChapterSummary summary = ChapterSummary.fromJson(
      decode(chapterSummaryJson),
    );
    expect(summary.id, 1);
    expect(summary.storyId, 1);
    expect(summary.index, 1);
    expect(summary.title, 'Chương 1: Kiếm Ngưng Tường');
    expect(summary.toJson()['index'], 1);

    final Chapter chapter = Chapter.fromJson(decode(chapterJson));
    expect(chapter.content, contains('biên thành'));
    expect(Chapter.fromJson(chapter.toJson()).content, chapter.content);
  });

  test('User đọc JSON trả về từ /auth/login', () {
    final Map<String, dynamic> body = decode(loginJson);
    expect(body['token'], isNotEmpty);

    final User user = User.fromJson(body['user']! as Map<String, dynamic>);
    expect(user.id, 2);
    expect(user.name, 'Lê Minh Anh');
    expect(user.email, 'docgia@vietread.vn');
    expect(user.avatarUrl, isNull);
    expect(user.initial, 'L');
    expect(User.fromJson(user.toJson()).email, user.email);
  });

  test('Comment đọc đúng schema Phần B', () {
    final Comment comment = Comment.fromJson(decode(commentJson));

    expect(comment.chapterId, isNull);
    expect(comment.userName, 'Lê Minh Anh');
    expect(comment.content, contains('ra chương nhanh'));
    expect(comment.initial, 'L');
    expect(Comment.fromJson(comment.toJson()).userId, comment.userId);
  });

  test('ImportJob đọc cả 2 shape của API import và có nhãn tiếng Việt', () {
    // POST /imports → { jobId }
    final ImportJob created = ImportJob.fromJson(<String, dynamic>{'jobId': 7});
    expect(created.jobId, 7);
    expect(created.isPending, isTrue);
    expect(created.statusLabel, 'Đang chờ');

    // GET /imports/{id} → { status, progress, storyId?, error? }
    final ImportJob running = ImportJob.fromJson(<String, dynamic>{
      'jobId': 7,
      'status': 'Running',
      'progress': 45,
      'storyId': null,
      'error': null,
    });
    expect(running.progress01, closeTo(0.45, 0.001));
    expect(running.statusLabel, 'Đang chạy');

    final ImportJob failed = ImportJob.fromJson(<String, dynamic>{
      'jobId': 8,
      'status': 'Failed',
      'progress': 10,
      'error': 'Nguồn chặn yêu cầu',
    });
    expect(failed.isFailed, isTrue);
    expect(failed.statusLabel, 'Thất bại');
    expect(failed.error, 'Nguồn chặn yêu cầu');
    expect(ImportJob.fromJson(failed.toJson()).jobId, 8);
  });
}
