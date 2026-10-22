import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chapter.dart';
import '../models/comment.dart';
import '../models/genre.dart';
import '../models/glossary.dart';
import '../models/import_job.dart';
import '../models/story.dart';
import '../models/story_word.dart';
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
  ///
  /// Mặc định trả bản **đã resolve** (bỏ marker nhiều nghĩa) cho người đọc;
  /// `raw: true` (`?raw=1`) trả bản thô có marker — chỉ chủ truyện dùng khi
  /// sửa chương để chọn nghĩa.
  Future<Chapter> fetchChapter(int chapterId, {bool raw = false});

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
    String? originalAuthor,
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
    String? originalAuthor,
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

  // ------------------------- Thêm chương vào truyện đã có ------------------

  /// POST /stories/{id}/chapters/import — thêm chương từ link Qidian
  /// (chỉ chủ truyện; backend cào + dịch đồng bộ trong request).
  Future<Chapter> importChapterFromUrl(
    int storyId, {
    required String chapterUrl,
    int? chapterNo,
    String? title,
  });

  /// POST /stories/{id}/chapters/import-text — thêm chương bằng văn bản dán
  /// (`sourceLang`: 'zh' = dịch Trung → Việt, 'vi' = lưu nguyên).
  Future<Chapter> importChapterFromText(
    int storyId, {
    required String text,
    required String sourceLang,
    int? chapterNo,
    String? title,
  });

  // ------------------------- Sửa bản dịch: marker + thay thế ----------------

  /// POST /chapters/{id}/retranslate — dịch lại từ `OriginalContent` bằng từ
  /// điển hiện tại (có marker). **Trả về để nạp vào màn Sửa chương, không lưu**
  /// — chỉ lưu khi người dùng bấm Lưu. [markLevel] — mức gợi ý
  /// (`low`/`medium`/`high`); `null` giữ nguyên trần mặc định của backend.
  Future<String> retranslateChapter(int chapterId, {String? markLevel});

  /// POST /stories/{id}/replace — tìm & thay thế trong MỘT truyện.
  /// `dryRun: true` chỉ đếm chỗ/chương, không ghi gì; thay thật trả `batchId`
  /// để gọi [undoReplace]. Thao tác trên bản thô (kể cả bên trong marker).
  Future<ReplaceResult> replaceInStory(
    int storyId, {
    required String find,
    required String replace,
    bool matchCase = false,
    bool wholeWord = false,
    bool includeTitles = false,
    bool applyToFuture = false,
    bool dryRun = false,
  });

  /// POST /stories/{id}/replace/undo — hoàn tác batch gần nhất; chương đã bị
  /// sửa tiếp sau batch thì bỏ qua và được báo trong `skipped`.
  Future<UndoResult> undoReplace(int storyId);

  /// GET /stories/{id}/glossary — quy tắc (A → B) đã lưu của truyện.
  Future<List<GlossaryRule>> fetchGlossary(int storyId);

  /// DELETE /stories/{id}/glossary/{ruleId} — xoá một quy tắc.
  Future<void> deleteGlossaryRule(int storyId, int ruleId);

  // ------------------------- Gợi ý nhiều nghĩa theo truyện ----------------

  /// GET /stories/{id}/word-choices — nghĩa đã chọn ("luôn dùng") của truyện.
  Future<List<WordChoice>> fetchWordChoices(int storyId);

  /// POST /stories/{id}/word-choices — chọn nghĩa cho marker (upsert).
  ///
  /// Gửi **danh sách nghĩa của marker** ([meanings]) — backend tra ngược khóa
  /// từ điển (mọi khóa trùng danh sách nghĩa) thay vì nhận chữ Hán.
  /// [sourceKey] chỉ kèm khi marker là dữ liệu cũ còn khóa (tương thích).
  Future<WordChoice> saveWordChoice(
    int storyId, {
    String? sourceKey,
    required String chosenText,
    List<String>? meanings,
  });

  /// DELETE /stories/{id}/word-choices/{choiceId} — bỏ nghĩa đã chọn.
  Future<void> deleteWordChoice(int storyId, int choiceId);

  /// GET /stories/{id}/ignored-words — từ đã đánh dấu “không hỏi lại”.
  Future<List<IgnoredWord>> fetchIgnoredWords(int storyId);

  /// POST /stories/{id}/ignored-words — “Không hỏi lại nữa” cho marker.
  ///
  /// Tương tự [saveWordChoice]: gửi [meanings] (khóa để backend tra ngược),
  /// [sourceKey] chỉ kèm với dữ liệu cũ còn khóa.
  Future<IgnoredWord> ignoreWord(
    int storyId, {
    String? sourceKey,
    List<String>? meanings,
  });

  /// DELETE /stories/{id}/ignored-words/{wordId} — bật lại câu hỏi.
  Future<void> deleteIgnoredWord(int storyId, int wordId);
}

/// Gọi REST API thật của backend FastAPI.
class HttpApiService implements ApiService {
  /// Callback cấp **static** — mọi instance đều gọi khi request trả **401**
  /// (token hết hạn / sai khoá ký / đã bị xoá). `AuthService` đăng ký để tự
  /// xoá phiên ngay, UI chuyển về màn đăng nhập thay vì kẹt ở trạng thái
  /// "đã đăng nhập" mà mọi request đều lỗi "Token không hợp lệ hoặc đã hết hạn".
  static void Function()? onUnauthorized;

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
    Duration? timeout,
  }) async {
    final http.Response res;
    try {
      final http.Request request = http.Request(method, _uri(path, query))
        ..headers.addAll(_headers);
      if (payload != null) request.body = jsonEncode(payload);
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(timeout ?? ApiConfig.requestTimeout);
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

    // 401 khi đang gọi với token = phiên đã chết → báo cho AuthService tự
    // đăng xuất. Bỏ qua /auth/login + /auth/register (401 = sai mật khẩu,
    // không liên quan tới phiên hiện tại).
    if (res.statusCode == 401 &&
        path != '/auth/login' &&
        path != '/auth/register') {
      HttpApiService.onUnauthorized?.call();
    }

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
  Future<Chapter> fetchChapter(int chapterId, {bool raw = false}) async {
    final dynamic data = await _get(
      '/chapters/$chapterId',
      query: raw ? <String, String>{'raw': '1'} : null,
    );
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
    return data
        .whereType<Map<String, dynamic>>()
        .map(Comment.fromJson)
        .toList();
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
    String? originalAuthor,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/stories',
      payload: <String, dynamic>{
        'title': title.trim(),
        if (_cleanField(description) != null)
          'description': _cleanField(description),
        if (_cleanField(coverUrl) != null) 'coverUrl': _cleanField(coverUrl),
        if (_cleanField(originalAuthor) != null)
          'originalAuthor': _cleanField(originalAuthor),
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
    String? originalAuthor,
  }) async {
    final dynamic data = await _request(
      'PUT',
      '/stories/$storyId',
      payload: <String, dynamic>{
        if (title != null) 'title': title.trim(),
        // Kèm key + null để backend xoá trường (exclude_unset của Pydantic).
        if (description != null) 'description': _cleanField(description),
        if (coverUrl != null) 'coverUrl': _cleanField(coverUrl),
        // Chuỗi rỗng → null = xoá tác giả (lưu NULL).
        if (originalAuthor != null)
          'originalAuthor': _cleanField(originalAuthor),
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

  // ------------------------- Thêm chương vào truyện đã có ------------------

  @override
  Future<Chapter> importChapterFromUrl(
    int storyId, {
    required String chapterUrl,
    int? chapterNo,
    String? title,
  }) async {
    // Timeout riêng: backend cào + dịch đồng bộ trong request (~60s).
    final dynamic data = await _request(
      'POST',
      '/stories/$storyId/chapters/import',
      payload: <String, dynamic>{
        'chapterUrl': chapterUrl.trim(),
        'chapterNo': ?chapterNo,
        'title': ?title,
      },
      timeout: ApiConfig.importChapterTimeout,
    );
    return _readChapter(data);
  }

  @override
  Future<Chapter> importChapterFromText(
    int storyId, {
    required String text,
    required String sourceLang,
    int? chapterNo,
    String? title,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/stories/$storyId/chapters/import-text',
      payload: <String, dynamic>{
        'text': text,
        'sourceLang': sourceLang,
        'chapterNo': ?chapterNo,
        'title': ?title,
      },
      timeout: ApiConfig.importChapterTimeout,
    );
    return _readChapter(data);
  }

  // ------------------------- Sửa bản dịch: marker + thay thế ----------------

  @override
  Future<String> retranslateChapter(int chapterId, {String? markLevel}) async {
    final dynamic data = await _request(
      'POST',
      '/chapters/$chapterId/retranslate',
      payload: markLevel == null
          ? null
          : <String, dynamic>{'markLevel': markLevel},
    );
    if (data is! Map<String, dynamic> || data['content'] is! String) {
      throw const ApiException('Phản hồi dịch lại chương không hợp lệ.');
    }
    return data['content'] as String;
  }

  @override
  Future<ReplaceResult> replaceInStory(
    int storyId, {
    required String find,
    required String replace,
    bool matchCase = false,
    bool wholeWord = false,
    bool includeTitles = false,
    bool applyToFuture = false,
    bool dryRun = false,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/stories/$storyId/replace',
      payload: <String, dynamic>{
        'find': find,
        'replace': replace,
        'matchCase': matchCase,
        'wholeWord': wholeWord,
        'includeTitles': includeTitles,
        'applyToFuture': applyToFuture,
        'dryRun': dryRun,
      },
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi tìm & thay thế không hợp lệ.');
    }
    return ReplaceResult.fromJson(data);
  }

  @override
  Future<UndoResult> undoReplace(int storyId) async {
    final dynamic data = await _request(
      'POST',
      '/stories/$storyId/replace/undo',
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi hoàn tác không hợp lệ.');
    }
    return UndoResult.fromJson(data);
  }

  @override
  Future<List<GlossaryRule>> fetchGlossary(int storyId) async {
    final dynamic data = await _get('/stories/$storyId/glossary');
    if (data is! List) {
      throw const ApiException('Danh sách quy tắc không hợp lệ.');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(GlossaryRule.fromJson)
        .toList();
  }

  @override
  Future<void> deleteGlossaryRule(int storyId, int ruleId) async {
    await _request('DELETE', '/stories/$storyId/glossary/$ruleId');
  }

  // ------------------------- Gợi ý nhiều nghĩa theo truyện ----------------

  @override
  Future<List<WordChoice>> fetchWordChoices(int storyId) async {
    final dynamic data = await _get('/stories/$storyId/word-choices');
    if (data is! List) {
      throw const ApiException('Danh sách nghĩa đã chọn không hợp lệ.');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(WordChoice.fromJson)
        .toList();
  }

  @override
  Future<WordChoice> saveWordChoice(
    int storyId, {
    String? sourceKey,
    required String chosenText,
    List<String>? meanings,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/stories/$storyId/word-choices',
      payload: <String, dynamic>{
        if (sourceKey != null && sourceKey.isNotEmpty) 'sourceKey': sourceKey,
        'chosenText': chosenText,
        if (meanings != null && meanings.isNotEmpty) 'meanings': meanings,
      },
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi lưu nghĩa không hợp lệ.');
    }
    return WordChoice.fromJson(data);
  }

  @override
  Future<void> deleteWordChoice(int storyId, int choiceId) async {
    await _request('DELETE', '/stories/$storyId/word-choices/$choiceId');
  }

  @override
  Future<List<IgnoredWord>> fetchIgnoredWords(int storyId) async {
    final dynamic data = await _get('/stories/$storyId/ignored-words');
    if (data is! List) {
      throw const ApiException('Danh sách từ đã bỏ qua không hợp lệ.');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(IgnoredWord.fromJson)
        .toList();
  }

  @override
  Future<IgnoredWord> ignoreWord(
    int storyId, {
    String? sourceKey,
    List<String>? meanings,
  }) async {
    final dynamic data = await _request(
      'POST',
      '/stories/$storyId/ignored-words',
      payload: <String, dynamic>{
        if (sourceKey != null && sourceKey.isNotEmpty) 'sourceKey': sourceKey,
        if (meanings != null && meanings.isNotEmpty) 'meanings': meanings,
      },
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi bỏ qua từ không hợp lệ.');
    }
    return IgnoredWord.fromJson(data);
  }

  @override
  Future<void> deleteIgnoredWord(int storyId, int wordId) async {
    await _request('DELETE', '/stories/$storyId/ignored-words/$wordId');
  }
}
