import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chapter.dart';
import '../models/comment.dart';
import '../models/genre.dart';
import '../models/import_job.dart';
import '../models/story.dart';
import '../models/user.dart';
import 'api_config.dart';
import 'mock_api_service.dart';

/// Lỗi API — luôn kèm thông báo tiếng Việt thân thiện để hiện cho người dùng (A6).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Kết quả đăng nhập / đăng ký — khớp `{ token, user }` của backend (Bước 6).
class AuthResult {
  const AuthResult({required this.token, required this.user});

  final String token;
  final User user;
}

/// Giao diện chung của mọi nguồn dữ liệu.
///
/// `MockApiService` (Bước 4) và `HttpApiService` (Bước 6) cùng implements interface này,
/// nên chuyển sang API thật chỉ cần đổi cờ `ApiConfig.useMock`.
abstract class ApiService {
  /// Tạo service theo cờ cấu hình (A6: đổi 1 cờ là xong).
  factory ApiService() =>
      ApiConfig.useMock ? MockApiService() : HttpApiService();

  /// GET /genres → [{ id, name }]
  Future<List<Genre>> fetchGenres();

  /// GET /stories?query=&genre=&status=&sort=&page=&pageSize=
  Future<List<Story>> fetchStories({
    String? query,
    String? genre,
    String? status,
    String sort = 'newest',
    int page = 1,
    int pageSize = 12,
  });

  /// GET /stories/{id} — chi tiết một truyện (Bước 5).
  Future<Story> fetchStory(int storyId);

  /// GET /stories/{id}/chapters?page=&pageSize= — danh sách chương (Bước 5).
  Future<List<ChapterSummary>> fetchChapters(
    int storyId, {
    int page = 1,
    int pageSize = 50,
  });

  /// GET /chapters/{id} — nội dung chương (Bước 5).
  Future<Chapter> fetchChapter(int chapterId);

  // ------------------------- Xác thực (Bước 6) -------------------------

  /// Gắn token cho các request kế tiếp (`null` = đăng xuất).
  void setToken(String? token);

  /// POST /auth/login → { token, user }.
  Future<AuthResult> login(String email, String password);

  /// POST /auth/register → { token, user }.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  });

  /// GET /auth/me — kiểm tra token đã lưu còn hiệu lực không.
  Future<User> fetchMe();

  // ------------------------- Theo dõi truyện (Bước 7) -------------------------

  /// GET /me/follows — danh sách truyện người dùng đang theo dõi.
  Future<List<Story>> fetchMyFollows();

  /// POST /follows/{storyId} — theo dõi một truyện (idempotent).
  Future<void> followStory(int storyId);

  /// DELETE /follows/{storyId} — bỏ theo dõi (idempotent).
  Future<void> unfollowStory(int storyId);

  // ------------------------- Bình luận (Bước 8) -------------------------

  /// GET /stories/{id}/comments — danh sách bình luận theo truyện (mới nhất trước).
  Future<List<Comment>> fetchComments(int storyId);

  /// POST /stories/{id}/comments — gửi bình luận (bắt buộc đăng nhập).
  Future<Comment> addComment(int storyId, String content, {int? chapterId});

  /// DELETE /comments/{id} — xoá bình luận của chính mình.
  Future<void> deleteComment(int commentId);

  // ------------------------- Đăng truyện — CRUD (Bước 9) -------------------------

  /// GET /me/stories — truyện của tôi, **kể cả nháp** (mới nhất trước).
  Future<List<Story>> fetchMyStories();

  /// POST /stories — tạo truyện; `genres` là tên thể loại (chưa có backend tự tạo).
  Future<Story> createStory({
    required String title,
    String? description,
    String? coverUrl,
    String status = 'ongoing',
    List<String> genres = const <String>[],
    bool isDraft = false,
  });

  /// PUT /stories/{id} — sửa truyện; trường truyền `null` thì giữ nguyên,
  /// `description`/`coverUrl` truyền chuỗi rỗng thì xoá.
  Future<Story> updateStory(
    int storyId, {
    String? title,
    String? description,
    String? coverUrl,
    String? status,
    List<String>? genres,
    bool? isDraft,
  });

  /// DELETE /stories/{id} — xoá truyện (chỉ tác giả).
  Future<void> deleteStory(int storyId);

  /// POST /stories/{id}/chapters — thêm chương; `index` null = tự đánh số tiếp.
  Future<Chapter> createChapter(
    int storyId, {
    required String title,
    required String content,
    int? index,
  });

  /// PUT /chapters/{id} — sửa chương; trường truyền `null` thì giữ nguyên.
  Future<Chapter> updateChapter(
    int chapterId, {
    String? title,
    String? content,
    int? index,
  });

  /// DELETE /chapters/{id} — xoá chương (chỉ tác giả).
  Future<void> deleteChapter(int chapterId);

  // ------------------------- Nhập truyện từ link (Bước 10) ------------------

  /// POST /imports — tạo job nhập truyện từ link, trả về `jobId` để poll.
  Future<int> startImport({
    required String sourceUrl,
    String targetLang = 'vi',
  });

  /// GET /imports/{jobId} — trạng thái job (Pending/Running/Done/Failed + %).
  Future<ImportJob> fetchImportJob(int jobId);
}

/// Gọi REST API thật của backend FastAPI.
class HttpApiService implements ApiService {
  HttpApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;

  /// Có thể ghi đè để test hoặc trỏ sang host khác.
  final String _baseUrl;

  /// Token JWT đang giữ trong bộ nhớ — đính kèm header Authorization (Bước 6).
  String? _token;

  @override
  void setToken(String? token) => _token = token;

  Uri _uri(String path, [Map<String, String>? query]) {
    final Uri base = Uri.parse('$_baseUrl$path');
    return query == null ? base : base.replace(queryParameters: query);
  }

  /// Header JSON + `Authorization: Bearer <token>` khi đã đăng nhập.
  Map<String, String> get _headers => <String, String>{
    'Content-Type': 'application/json; charset=utf-8',
    if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  /// Gửi request bất kỳ và decode JSON; mọi lỗi đều chuyển sang
  /// `ApiException` tiếng Việt (A6: timeout + thông báo thân thiện).
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
  }) async {
    final http.Response res;
    try {
      final http.Request request = http.Request(method, _uri(path, query))
        ..headers.addAll(_headers);
      if (payload != null) request.body = jsonEncode(payload);
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(ApiConfig.requestTimeout);
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException('Máy chủ phản hồi quá chậm, vui lòng thử lại.');
    } catch (_) {
      // Không có mạng / sai địa chỉ / DNS lỗi...
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra Wi-Fi và địa chỉ API.',
      );
    }

    // bodyBytes + utf8: backend trả JSON không ghi charset, tránh lỗi tiếng Việt
    final String body = utf8.decode(res.bodyBytes, allowMalformed: true);

    if (res.statusCode != 200) {
      String message = 'Đã xảy ra lỗi (${res.statusCode}), vui lòng thử lại.';
      try {
        final dynamic decoded = jsonDecode(body);
        if (decoded is Map && decoded['message'] is String) {
          message = decoded['message'] as String;
        }
      } catch (_) {}
      throw ApiException(message, statusCode: res.statusCode);
    }

    try {
      return jsonDecode(body);
    } catch (_) {
      throw const ApiException('Dữ liệu nhận được từ máy chủ không hợp lệ.');
    }
  }

  /// GET và decode JSON.
  Future<dynamic> _get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);

  @override
  Future<List<Genre>> fetchGenres() async {
    final dynamic data = await _get('/genres');
    if (data is! List) {
      throw const ApiException('Dữ liệu thể loại không hợp lệ.');
    }
    return data.whereType<Map<String, dynamic>>().map(Genre.fromJson).toList();
  }

  @override
  Future<List<Story>> fetchStories({
    String? query,
    String? genre,
    String? status,
    String sort = 'newest',
    int page = 1,
    int pageSize = 12,
  }) async {
    final Map<String, String> params = <String, String>{
      'sort': sort,
      'page': '$page',
      'pageSize': '$pageSize',
    };
    if (query != null && query.trim().isNotEmpty) {
      params['query'] = query.trim();
    }
    if (genre != null && genre.trim().isNotEmpty) {
      params['genre'] = genre.trim();
    }
    if (status != null && status.isNotEmpty) {
      params['status'] = status;
    }

    final dynamic data = await _get('/stories', query: params);
    if (data is! List) {
      throw const ApiException('Dữ liệu truyện không hợp lệ.');
    }
    return data.whereType<Map<String, dynamic>>().map(Story.fromJson).toList();
  }

  @override
  Future<Story> fetchStory(int storyId) async {
    final dynamic data = await _get('/stories/$storyId');
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Dữ liệu truyện không hợp lệ.');
    }
    return Story.fromJson(data);
  }

  @override
  Future<List<ChapterSummary>> fetchChapters(
    int storyId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final dynamic data = await _get(
      '/stories/$storyId/chapters',
      query: {'page': '$page', 'pageSize': '$pageSize'},
    );
    if (data is! List) {
      throw const ApiException('Danh sách chương không hợp lệ.');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(ChapterSummary.fromJson)
        .toList();
  }

  @override
  Future<Chapter> fetchChapter(int chapterId) async {
    final dynamic data = await _get('/chapters/$chapterId');
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Nội dung chương không hợp lệ.');
    }
    return Chapter.fromJson(data);
  }

  // ------------------------- Xác thực (Bước 6) -------------------------

  /// Đọc `{ token, user }` từ response rồi giữ token cho các request sau.
  AuthResult _readAuthResult(dynamic data) {
    if (data is! Map<String, dynamic> ||
        data['token'] is! String ||
        data['user'] is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi đăng nhập không hợp lệ.');
    }
    final AuthResult result = AuthResult(
      token: data['token'] as String,
      user: User.fromJson(data['user'] as Map<String, dynamic>),
    );
    _token = result.token;
    return result;
  }

  @override
  Future<AuthResult> login(String email, String password) async {
    final dynamic data = await _request(
      'POST',
      '/auth/login',
      payload: <String, dynamic>{'email': email.trim(), 'password': password},
    );
    return _readAuthResult(data);
  }

  @override
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/auth/register',
      payload: <String, dynamic>{
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
      },
    );
    return _readAuthResult(data);
  }

  @override
  Future<User> fetchMe() async {
    final dynamic data = await _get('/auth/me');
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Dữ liệu tài khoản không hợp lệ.');
    }
    return User.fromJson(data);
  }

  // ------------------------- Theo dõi truyện (Bước 7) -------------------------

  @override
  Future<List<Story>> fetchMyFollows() async {
    final dynamic data = await _get('/me/follows');
    if (data is! List) {
      throw const ApiException('Danh sách theo dõi không hợp lệ.');
    }
    return data.whereType<Map<String, dynamic>>().map(Story.fromJson).toList();
  }

  @override
  Future<void> followStory(int storyId) async {
    await _request('POST', '/follows/$storyId');
  }

  @override
  Future<void> unfollowStory(int storyId) async {
    await _request('DELETE', '/follows/$storyId');
  }

  // ------------------------- Bình luận (Bước 8) -------------------------

  @override
  Future<List<Comment>> fetchComments(int storyId) async {
    final dynamic data = await _get('/stories/$storyId/comments');
    if (data is! List) {
      throw const ApiException('Danh sách bình luận không hợp lệ.');
    }
    return data.whereType<Map<String, dynamic>>().map(Comment.fromJson).toList();
  }

  @override
  Future<Comment> addComment(
    int storyId,
    String content, {
    int? chapterId,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/stories/$storyId/comments',
      payload: <String, dynamic>{'content': content, 'chapterId': chapterId},
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi bình luận không hợp lệ.');
    }
    return Comment.fromJson(data);
  }

  @override
  Future<void> deleteComment(int commentId) async {
    await _request('DELETE', '/comments/$commentId');
  }

  // ------------------------- Đăng truyện — CRUD (Bước 9) -------------------------

  /// Đọc object `Story` từ response, hoặc ném lỗi nếu dữ liệu không hợp lệ.
  Story _readStory(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Dữ liệu truyện không hợp lệ.');
    }
    return Story.fromJson(data);
  }

  /// Đọc object `Chapter` từ response.
  Chapter _readChapter(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Dữ liệu chương không hợp lệ.');
    }
    return Chapter.fromJson(data);
  }

  /// Chuỗi rỗng / toàn khoảng trắng → `null` (xoá trường) — khớp backend.
  static String? _cleanField(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<List<Story>> fetchMyStories() async {
    final dynamic data = await _get('/me/stories');
    if (data is! List) {
      throw const ApiException('Danh sách truyện không hợp lệ.');
    }
    return data.whereType<Map<String, dynamic>>().map(Story.fromJson).toList();
  }

  @override
  Future<Story> createStory({
    required String title,
    String? description,
    String? coverUrl,
    String status = 'ongoing',
    List<String> genres = const <String>[],
    bool isDraft = false,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/stories',
      payload: <String, dynamic>{
        'title': title.trim(),
        if (_cleanField(description) != null) 'description': _cleanField(description),
        if (_cleanField(coverUrl) != null) 'coverUrl': _cleanField(coverUrl),
        'status': status,
        'genres': genres,
        'isDraft': isDraft,
      },
    );
    return _readStory(data);
  }

  @override
  Future<Story> updateStory(
    int storyId, {
    String? title,
    String? description,
    String? coverUrl,
    String? status,
    List<String>? genres,
    bool? isDraft,
  }) async {
    final dynamic data = await _request(
      'PUT',
      '/stories/$storyId',
      payload: <String, dynamic>{
        if (title != null) 'title': title.trim(),
        // Kèm key + null để backend xoá trường (exclude_unset của Pydantic).
        if (description != null) 'description': _cleanField(description),
        if (coverUrl != null) 'coverUrl': _cleanField(coverUrl),
        'status': ?status,
        'genres': ?genres,
        'isDraft': ?isDraft,
      },
    );
    return _readStory(data);
  }

  @override
  Future<void> deleteStory(int storyId) async {
    await _request('DELETE', '/stories/$storyId');
  }

  @override
  Future<Chapter> createChapter(
    int storyId, {
    required String title,
    required String content,
    int? index,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/stories/$storyId/chapters',
      payload: <String, dynamic>{
        'title': title.trim(),
        'content': content,
        'index': ?index,
      },
    );
    return _readChapter(data);
  }

  @override
  Future<Chapter> updateChapter(
    int chapterId, {
    String? title,
    String? content,
    int? index,
  }) async {
    // Không gửi key khi value null — backend coi index=null là lỗi 400.
    final dynamic data = await _request(
      'PUT',
      '/chapters/$chapterId',
      payload: <String, dynamic>{
        if (title != null) 'title': title.trim(),
        'content': ?content,
        'index': ?index,
      },
    );
    return _readChapter(data);
  }

  @override
  Future<void> deleteChapter(int chapterId) async {
    await _request('DELETE', '/chapters/$chapterId');
  }

  @override
  Future<int> startImport({
    required String sourceUrl,
    String targetLang = 'vi',
  }) async {
    final dynamic data = await _request(
      'POST',
      '/imports',
      payload: <String, dynamic>{
        'sourceUrl': sourceUrl.trim(),
        'targetLang': targetLang,
      },
    );
    if (data is! Map<String, dynamic> || data['jobId'] == null) {
      throw const ApiException('Phản hồi tạo import job không hợp lệ.');
    }
    return (data['jobId'] as num).toInt();
  }

  @override
  Future<ImportJob> fetchImportJob(int jobId) async {
    final dynamic data = await _get('/imports/$jobId');
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Dữ liệu import job không hợp lệ.');
    }
    return ImportJob.fromJson(data);
  }
}
