// Kiểm tra `HttpApiService` gọi backend FastAPI thật
// (đường đi của cờ `ApiConfig.useMock = false`).
//
// Chạy:
//   dart run tool/check_real_api.dart http://127.0.0.1:8000
//
// In ra thể loại + truyện từ backend; sau đó thử cổng sai để xem
// thông báo lỗi tiếng Việt mà app sẽ hiện cho người dùng (A6).
import 'dart:io' show stdout;

import 'package:vietread/models/comment.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/models/user.dart';
import 'package:vietread/services/api_config.dart';
import 'package:vietread/services/api_service.dart';

Future<void> main(List<String> args) async {
  final String baseUrl = args.isNotEmpty
      ? args.first
      : ApiConfig.baseUrl; // mặc định 10.0.2.2:8000
  stdout.writeln('API_BASE_URL = $baseUrl');

  final HttpApiService api = HttpApiService(baseUrl: baseUrl);

  try {
    final genres = await api.fetchGenres();
    stdout.writeln(
      'GET /genres → ${genres.length} thể loại: ${genres.take(4).map((g) => g.name).join(", ")}...',
    );

    final stories = await api.fetchStories(sort: 'rating', pageSize: 3);
    stdout.writeln(
      'GET /stories?sort=rating&pageSize=3 → ${stories.length} truyện:',
    );
    for (final s in stories) {
      stdout.writeln(
        '  - ${s.title} | ${s.author} | ${s.ratingLabel} '
        '| ${s.chapterLabel} | ${s.genres.join(", ")} | ${s.statusLabel}',
      );
    }

    final filtered = await api.fetchStories(query: 'Kiếm Sư', pageSize: 5);
    stdout.writeln(
      'GET /stories?query=Kiếm Sư → ${filtered.length} kết quả'
      '${filtered.isEmpty ? "" : " (${filtered.first.title})"}',
    );

    // ----- Bước 5: chi tiết truyện + danh sách chương + nội dung chương -----
    if (stories.isNotEmpty) {
      final int storyId = stories.first.id;

      final detail = await api.fetchStory(storyId);
      stdout.writeln(
        'GET /stories/$storyId → ${detail.title} | '
        '${detail.chapterLabel} | ${detail.statusLabel}',
      );

      final chapters = await api.fetchChapters(storyId, page: 1, pageSize: 5);
      stdout.writeln(
        'GET /stories/$storyId/chapters → ${chapters.length} chương'
        '${chapters.isEmpty ? "" : ": ${chapters.first.title} ... ${chapters.last.title}"}',
      );

      if (chapters.isNotEmpty) {
        final chapter = await api.fetchChapter(chapters.first.id);
        final int chars = chapter.content.length;
        stdout.writeln(
          'GET /chapters/${chapters.first.id} → ${chapter.title} | '
          '$chars ký tự nội dung',
        );
        if (chars == 0) {
          stdout.writeln('CẢNH BÁO: nội dung chương trống');
        }
      }
    }
    // ----- Bước 6: xác thực (đăng ký / đăng nhập / token Bearer) -----
    final String tempEmail =
        'test${DateTime.now().millisecondsSinceEpoch}@vietread.vn';
    final AuthResult registered = await api.register(
      name: 'Nguoi Thu Test',
      email: tempEmail,
      password: '123456',
    );
    stdout.writeln(
      'POST /auth/register → ${registered.user.email} | token ${registered.token.length} ký tự',
    );

    // _readAuthResult đã giữ token; gọi /auth/me để xác nhận header Bearer
    final User me = await api.fetchMe();
    stdout.writeln('GET /auth/me (Bearer) → ${me.name} | ${me.email}');

    api.setToken(null); // đăng xuất giả
    final AuthResult demo = await api.login(
      'docgia@vietread.vn',
      'VietRead@123',
    );
    stdout.writeln('POST /auth/login (tài khoản demo) → ${demo.user.email}');

    // Sai mật khẩu → phải nhận 401 với thông báo tiếng Việt (A6)
    try {
      await api.login('docgia@vietread.vn', 'sai-mat-khau');
      stdout.writeln('Kỳ lạ: sai mật khẩu vẫn đăng nhập được?');
    } on ApiException catch (e) {
      stdout.writeln('Sai mật khẩu → [${e.statusCode}] "${e.message}"');
      // ----- Bước 7: theo dõi truyện (POST/DELETE /follows, GET /me/follows) -----

      final int followId = stories.isNotEmpty ? stories.first.id : 1;
      try {
        await api.unfollowStory(followId); // dọn trạng thái của lần chạy trước
      } on ApiException {
        // chưa theo dõi sẵn hoặc truyện không tồn tại — bỏ qua
      }

      await api.followStory(followId);
      final List<Story> afterFollow = await api.fetchMyFollows();
      stdout.writeln(
        'POST /follows/$followId → /me/follows có ${afterFollow.length} truyện: '
        '${afterFollow.map((Story s) => s.title).join(", ")}',
      );

      await api.unfollowStory(followId);
      final List<Story> afterUnfollow = await api.fetchMyFollows();
      stdout.writeln(
        'DELETE /follows/$followId → còn theo dõi $followId: '
        '${afterUnfollow.any((Story s) => s.id == followId)}',
      );

      api.setToken(null); // chưa đăng nhập
      try {
        await api.fetchMyFollows();
        stdout.writeln('Kỳ lạ: /me/follows không token vẫn gọi được?');
      } on ApiException catch (e) {
        stdout.writeln(
          'GET /me/follows chưa đăng nhập → [${e.statusCode}] "${e.message}"',
        );
      }

      // ----- Bước 8: bình luận (GET/POST /stories/{id}/comments, DELETE) -----
      final int commentStoryId = stories.isNotEmpty ? stories.first.id : 1;

      final List<Comment> before = await api.fetchComments(commentStoryId);
      stdout.writeln(
        'GET /stories/$commentStoryId/comments → ${before.length} bình luận',
      );

      api.setToken(null); // chưa đăng nhập
      try {
        await api.addComment(commentStoryId, 'Không nên gọi được');
        stdout.writeln('Kỳ lạ: gửi comment không token vẫn thành công?');
      } on ApiException catch (e) {
        stdout.writeln(
          'POST comments chưa đăng nhập → [${e.statusCode}] "${e.message}"',
        );
      }

      final AuthResult demoLogin = await api.login(
        'docgia@vietread.vn',
        'VietRead@123',
      );
      final Comment posted = await api.addComment(
        commentStoryId,
        'Bình luận kiểm thử từ check_real_api (Bước 8).',
      );
      stdout.writeln(
        'POST /stories/$commentStoryId/comments → id ${posted.id} '
        '| ${posted.userName} | "${posted.content}"',
      );

      final List<Comment> afterPost = await api.fetchComments(commentStoryId);
      stdout.writeln('GET comments lần 2 → ${afterPost.length} bình luận');

      await api.deleteComment(posted.id);
      final List<Comment> afterDelete = await api.fetchComments(commentStoryId);
      stdout.writeln(
        'DELETE /comments/${posted.id} → còn ${afterDelete.length} bình luận '
        '${afterDelete.any((Comment c) => c.id == posted.id) ? "(SAI!)" : "(đúng)"}',
      );
      api.setToken(demoLogin.token);
    }
  } on ApiException catch (e) {
    stdout.writeln(
      'LỖI (ApiException): ${e.message} [${e.statusCode ?? "no status"}]',
    );
    return;
  }

  // Gọi cổng sai → phải nhận thông báo tiếng Việt thân thiện
  try {
    await HttpApiService(baseUrl: 'http://127.0.0.1:9999').fetchGenres();
    stdout.writeln('Kỳ lạ: gọi cổng sai vẫn thành công?');
  } on ApiException catch (e) {
    stdout.writeln('Gọi cổng sai → thông báo tiếng Việt: "${e.message}"');
  }
}
