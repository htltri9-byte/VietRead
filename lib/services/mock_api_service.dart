import 'dart:math';

import '../models/chapter.dart';
import '../models/comment.dart';
import '../models/genre.dart';
import '../models/glossary.dart';
import '../models/import_job.dart';
import '../models/story.dart';
import '../models/story_word.dart';
import '../models/user.dart';
import '../utils/alternatives.dart';
import 'api_config.dart';
import 'api_service.dart';

/// Nguồn dữ liệu **mock** (Bước 4): không cần backend vẫn chạy được app,
/// có "giả lập độ trễ" để thấy skeleton loading.
///
/// Logic lọc / sắp xếp / phân trang làm giống hệt backend để Bước 6
/// chuyển sang API thật mà không đổi giao diện.
class MockApiService implements ApiService {
  MockApiService({
    this.latency = ApiConfig.mockLatency,
    this.useCoverImages = true,
  });

  /// Độ trễ giả lập (đặt `Duration.zero` trong test cho nhanh).
  final Duration latency;

  /// Bật/tắt ảnh bìa (test widget dùng `false` để không cần mạng).
  final bool useCoverImages;

  /// Giả lập độ trễ — `Duration.zero` thì xong ngay (không tạo timer nên
  /// test gọi API không cần bấm đồng hồ ảo vẫn chạy tiếp được).
  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  static const List<Genre> _genres = <Genre>[
    Genre(id: 1, name: 'Tiên Hiệp'),
    Genre(id: 2, name: 'Huyền Huyễn'),
    Genre(id: 3, name: 'Kiếm Hiệp'),
    Genre(id: 4, name: 'Đô Thị'),
    Genre(id: 5, name: 'Ngôn Tình'),
    Genre(id: 6, name: 'Xuyên Không'),
    Genre(id: 7, name: 'Hệ Thống'),
    Genre(id: 8, name: 'Trinh Thám'),
  ];

  /// Dữ liệu mẫu: `updatedAgo` = thời gian cập nhật "mấy ... trước",
  /// `hot` = chỉ số popularity để xếp hạng mục "Đang hot".
  static List<_MockStory> _stories = _seedStories();

  /// Truyện seed gốc — [_stories] dựng lại từ đây khi reset (test).
  static List<_MockStory> _seedStories() => <_MockStory>[
    _MockStory(
      id: 1,
      title: 'Kiếm Sư Vọng Tường',
      author: 'Trần Nhật Nam',
      authorId: 1,
      genres: <String>['Tiên Hiệp', 'Kiếm Hiệp'],
      status: 'ongoing',
      rating: 4.5,
      chapterCount: 128,
      updatedAgo: const Duration(hours: 2),
      hot: 96,
      description: 'Một thiếu niên đói nghèo ở biên cương vô tình thức tỉnh kiếm ý vạn năm.',
    ),
    _MockStory(
      id: 2,
      title: 'Hoàng Đạo Chi Tâm',
      author: 'Trần Nhật Nam',
      authorId: 1,
      genres: <String>['Huyền Huyễn', 'Trinh Thám'],
      status: 'ongoing',
      rating: 4.8,
      chapterCount: 76,
      updatedAgo: const Duration(minutes: 35),
      hot: 91,
      description: 'Mười hai hoàng đạo rơi xuống nhân gian, ai nắm giữ tâm sao sẽ gánh nghiệp lực ấy.',
    ),
    _MockStory(
      id: 3,
      title: 'Phố Đèn Neon',
      author: 'Trần Nhật Nam',
      authorId: 1,
      genres: <String>['Đô Thị', 'Ngôn Tình'],
      status: 'completed',
      rating: 4.2,
      chapterCount: 54,
      updatedAgo: const Duration(days: 6),
      hot: 74,
      description: 'Cậu sinh viên giao hàng gặp cô gái bán hoa dưới đèn neon xanh giữa thành phố không ngủ.',
    ),
    _MockStory(
      id: 4,
      title: 'Xuyên Không Làm Giàu Ở Tống Triều',
      author: 'Trần Nhật Nam',
      authorId: 1,
      genres: <String>['Xuyên Không', 'Hệ Thống'],
      status: 'ongoing',
      rating: 4.1,
      chapterCount: 210,
      updatedAgo: const Duration(hours: 8),
      hot: 88,
      description: 'Một đầu bếp quán nhậu xuyên về thời Tống với công thức nước mắm và tham vọng mở chuỗi tiệm.',
    ),
    _MockStory(
      id: 5,
      title: 'Hệ Thống Treo Dọc Đêm',
      author: 'Lâm Gia Huy',
      authorId: 3,
      genres: <String>['Hệ Thống', 'Đô Thị'],
      status: 'ongoing',
      rating: 4.4,
      chapterCount: 99,
      updatedAgo: const Duration(minutes: 12),
      hot: 83,
      description: 'Mỗi nửa đêm hệ thống lại phát một nhiệm vụ, hoàn thành muộn một giây là mất tất cả.',
    ),
    _MockStory(
      id: 6,
      title: 'Mèo Đen Của Tiệm Sách Cũ',
      author: 'Vũ Thanh Hà',
      authorId: 4,
      genres: <String>['Ngôn Tình', 'Đô Thị'],
      status: 'completed',
      rating: 4.6,
      chapterCount: 42,
      updatedAgo: const Duration(days: 2),
      hot: 69,
      description: 'Tiệm sách cũ có một chú mèo đen, nó chọn sách theo... tâm trạng người mua.',
    ),
    _MockStory(
      id: 7,
      title: 'Bảy Ngày Trước Bình Minh',
      author: 'Nguyễn Hải Đăng',
      authorId: 5,
      genres: <String>['Trinh Thám'],
      status: 'ongoing',
      rating: 4.7,
      chapterCount: 61,
      updatedAgo: const Duration(hours: 5),
      hot: 79,
      description: 'Một vụ án lặp lại bảy lần, mỗi lần nạn nhân là một phiên bản khác của cùng một người.',
    ),
    _MockStory(
      id: 8,
      title: 'Lôi Đài Cuối Đời',
      author: 'Lâm Gia Huy',
      authorId: 3,
      genres: <String>['Kiếm Hiệp', 'Tiên Hiệp'],
      status: 'completed',
      rating: 3.9,
      chapterCount: 155,
      updatedAgo: const Duration(days: 11),
      hot: 58,
      description: 'Võ sĩ già nhận trận đấu cuối cùng, chỉ để truyền lại tuyệt kỹ cho kẻ chẳng ai thèm học.',
    ),
  ];

  /// Id truyện tiếp theo khi người dùng tạo mới (seed lớn nhất là 8).
  static int _nextStoryId = 9;

  /// Trả dữ liệu mock về đúng seed — dùng trong `setUp` của test widget
  /// để các test không dồn truyện / chương tạo trước đó (state là static).
  /// (Cố ý không dùng `@visibleForTesting` như các resetForTest khác.)
  static void resetStoriesForTest() {
    _stories = _seedStories();
    _chaptersByStory = <int, List<Chapter>>{};
    resetGlossaryForTest(); // quy tắc/thay thế gắn theo truyện → reset cùng
    _nextStoryId = 9;
    _nextChapterId = 5000000;
    _sourceBookByStory = <int, String>{};
    _sourceChaptersByStory = <int, Map<String, int>>{};
  }

  Story _toStory(_MockStory mock) => Story(
    id: mock.id,
    title: mock.title,
    author: mock.author,
    authorId: mock.authorId,
    // Ảnh bìa người dùng nhập luôn thắng ảnh picsum ngẫu nhiên.
    coverUrl:
        mock.coverUrl ??
        (useCoverImages
            ? 'https://picsum.photos/seed/vietread${mock.id}/400/600'
            : null),
    description: mock.description,
    genres: mock.genres,
    status: mock.status,
    rating: mock.rating,
    chapterCount: mock.chapterCount,
    isDraft: mock.isDraft,
    updatedAt: DateTime.now().subtract(mock.updatedAgo),
  );

  @override
  Future<List<Genre>> fetchGenres() async {
    await _wait();
    return List<Genre>.unmodifiable(_genres);
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
    await _wait();

    Iterable<_MockStory> result = _stories;

    // --- Lọc ---
    final String q = (query ?? '').trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where(
        (_MockStory s) =>
            s.title.toLowerCase().contains(q) ||
            s.author.toLowerCase().contains(q),
      );
    }
    final String g = (genre ?? '').trim();
    if (g.isNotEmpty) {
      result = result.where((_MockStory s) => s.genres.contains(g));
    }
    final String st = (status ?? '').trim();
    if (st.isNotEmpty) {
      result = result.where((_MockStory s) => s.status == st);
    }

    // Danh sách công khai luôn loại truyện nháp (giống backend).
    result = result.where((_MockStory s) => !s.isDraft);

    // --- Sắp xếp (cùng giá trị sort với backend) ---
    final List<_MockStory> sorted = result.toList();
    switch (sort) {
      case 'hot':
        sorted.sort((_MockStory a, _MockStory b) => b.hot.compareTo(a.hot));
        break;
      case 'rating':
        sorted.sort(
          (_MockStory a, _MockStory b) => b.rating.compareTo(a.rating),
        );
        break;
      case 'title':
        sorted.sort((_MockStory a, _MockStory b) => a.title.compareTo(b.title));
        break;
      default: // 'newest'
        sorted.sort(
          (_MockStory a, _MockStory b) => a.updatedAgo.compareTo(b.updatedAgo),
        );
    }

    // --- Phân trang ---
    final int start = max(0, (page - 1) * pageSize);
    if (start >= sorted.length) return <Story>[];
    final int end = min(sorted.length, start + pageSize);
    return sorted.sublist(start, end).map(_toStory).toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // Chi tiết truyện / chương (Bước 5)
  // ---------------------------------------------------------------------

  _MockStory? _mockById(int storyId) {
    for (final _MockStory s in _stories) {
      if (s.id == storyId) return s;
    }
    return null;
  }

  @override
  Future<Story> fetchStory(int storyId) async {
    await _wait();
    final _MockStory? mock = _mockById(storyId);
    if (mock == null) {
      throw const ApiException('Không tìm thấy truyện');
    }
    _requireViewable(mock); // nháp của người khác → 404 như backend
    return _toStory(mock);
  }

  /// Tiêu đề chương mẫu — xoay vòng để tạo dữ liệu mock.
  static const List<String> _chapterTitles = <String>[
    'Kiếm Ngưng Tường',
    'Trấn Thiên Tháp',
    'Lời Hứa Của Sư Phụ',
    'Đêm Trăng Cuối Cùng',
    'Bên Kia Ngọn Núi',
    'Tấm Bùa Màu Tro',
    'Cuộc Gặp Ở Chợ Đêm',
    'Bí Mật Trong Hang Đá',
    'Ngày Trở Về',
    'Trận Cuối',
    'Ánh Đèn Phía Trước',
    'Lá Thư Chưa Gửi',
  ];

  @override
  Future<List<ChapterSummary>> fetchChapters(
    int storyId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    await _wait();
    final _MockStory? mock = _mockById(storyId);
    if (mock == null) {
      throw const ApiException('Không tìm thấy truyện');
    }
    _requireViewable(mock); // nháp của người khác → 404 như backend

    // Truyện đã thao tác CRUD chương → lấy từ danh sách thật, xếp theo index.
    final List<Chapter>? custom = _chaptersByStory[storyId];
    if (custom != null) {
      final List<Chapter> sorted = List<Chapter>.of(custom)
        ..sort((Chapter a, Chapter b) => a.index.compareTo(b.index));
      final int start = max(0, (page - 1) * pageSize);
      if (start >= sorted.length) return <ChapterSummary>[];
      final int end = min(sorted.length, start + pageSize);
      final DateTime now = DateTime.now();
      return sorted
          .sublist(start, end)
          .map(
            (Chapter c) => ChapterSummary(
              id: c.id,
              storyId: c.storyId,
              index: c.index,
              title: c.title,
              updatedAt: now,
            ),
          )
          .toList(growable: false);
    }

    final int total = mock.chapterCount;
    final int start = max(0, (page - 1) * pageSize);
    if (start >= total) return <ChapterSummary>[];
    final int end = min(total, start + pageSize);

    final DateTime now = DateTime.now();
    return List<ChapterSummary>.generate(end - start, (int i) {
      final int index = start + i + 1;
      return ChapterSummary(
        id: chapterIdOf(storyId, index),
        storyId: storyId,
        index: index,
        title:
            'Chương $index: ${_chapterTitles[(index - 1) % _chapterTitles.length]}',
        updatedAt: now.subtract(Duration(days: total - index)),
      );
    });
  }

  @override
  Future<Chapter> fetchChapter(int chapterId, {bool raw = false}) async {
    await _wait();
    // Ưu tiên chương đã thao tác CRUD (id do mock cấp, không quy ước).
    final Chapter? custom = _findCustomChapter(chapterId);
    final Chapter chapter;
    if (custom != null) {
      _requireViewable(_storyOrThrow(custom.storyId));
      chapter = custom;
    } else {
      // Mock: id chương = storyId * 1000 + index (xem chapterIdOf)
      final int storyId = chapterId ~/ 1000;
      final int index = chapterId % 1000;
      final _MockStory? mock = _mockById(storyId);
      if (mock == null || index < 1 || index > mock.chapterCount) {
        throw const ApiException('Không tìm thấy chương');
      }
      final String title =
          'Chương $index: ${_chapterTitles[(index - 1) % _chapterTitles.length]}';
      chapter = Chapter(
        id: chapterId,
        storyId: storyId,
        index: index,
        title: title,
        content: _mockContent(mock, index),
      );
    }
    if (!raw) {
      // Người đọc: bản ĐÃ resolve (không marker) — như GET /chapters/{id}.
      return Chapter(
        id: chapter.id,
        storyId: chapter.storyId,
        index: chapter.index,
        title: chapter.title,
        content: resolveMarkers(chapter.content),
      );
    }
    // ?raw=1 — bản thô: 401 khi chưa đăng nhập, 403 khi không phải chủ truyện.
    if (_me == null) {
      throw const ApiException('Chưa đăng nhập (thiếu token)', statusCode: 401);
    }
    _requireOwner(_storyOrThrow(chapter.storyId));
    return chapter;
  }

  /// Mã hoá (storyId, index) thành id chương cho bản mock.
  static int chapterIdOf(int storyId, int index) => storyId * 1000 + index;

  // ------------------------- Xác thực (Bước 6) -------------------------

  /// Token giả lập — cùng vai trò với JWT của backend.
  String? _token;

  /// Token đã cấp còn hiệu lực (giống JWT: app khởi động lại vẫn dùng được).
  static final Map<String, User> _issuedTokens = <String, User>{};

  /// Người dùng hiện tại của phiên mock.
  User? _me;

  /// Email + mật khẩu đã "đăng ký" trong phiên mock (2 email demo của
  /// seed.sql dùng mật khẩu `VietRead@123`).
  final Map<String, String> _passwords = <String, String>{
    'tacgia@vietread.vn': 'VietRead@123',
    'docgia@vietread.vn': 'VietRead@123',
  };

  int _nextUserId = 100;

  @override
  void setToken(String? token) {
    _token = token;
    _me = token == null ? null : _issuedTokens[token];
  }

  @override
  Future<AuthResult> login(String email, String password) async {
    await _wait();
    final String mail = email.trim().toLowerCase();
    if (mail.isEmpty || password.isEmpty) {
      throw const ApiException(
        'Vui lòng nhập email và mật khẩu.',
        statusCode: 400,
      );
    }
    if (_passwords[mail] != password) {
      throw const ApiException(
        'Email hoặc mật khẩu không đúng',
        statusCode: 401,
      );
    }
    return _issue(mail);
  }

  @override
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await _wait();
    final String mail = email.trim().toLowerCase();
    if (name.trim().isEmpty) {
      throw const ApiException(
        'Tên hiển thị không được để trống',
        statusCode: 400,
      );
    }
    if (password.length < 6) {
      throw const ApiException(
        'Mật khẩu phải có ít nhất 6 ký tự',
        statusCode: 400,
      );
    }
    if (_passwords.containsKey(mail)) {
      throw const ApiException('Email đã được sử dụng', statusCode: 400);
    }
    _passwords[mail] = password;
    return _issue(mail, name: name.trim());
  }

  @override
  Future<User> fetchMe() async {
    await _wait();
    final User? me = _me;
    if (_token == null || me == null) {
      throw const ApiException(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
        statusCode: 401,
      );
    }
    return me;
  }

  /// Tạo token giả lập + thông tin người dùng cho email vừa đăng nhập.
  AuthResult _issue(String email, {String? name}) {
    // 2 tài khoản demo dùng id cố định khớp seed.sql (tacgia=1, docgia=2)
    // để "Truyện của tôi" (Bước 9) thấy đúng truyện mình là tác giả.
    final int id = switch (email) {
      'tacgia@vietread.vn' => 1,
      'docgia@vietread.vn' => 2,
      _ => _nextUserId++,
    };
    final User user = User(
      id: id,
      name: name ?? email.split('@').first,
      email: email,
    );
    _token = 'mock-token-${user.id}';
    _me = user;
    _issuedTokens[_token!] = user;
    return AuthResult(token: _token!, user: user);
  }

  // ------------------------- Theo dõi truyện (Bước 7) -------------------------

  /// Truyện đang theo dõi của từng người dùng (lưu static để giữ
  /// qua các lần mở lại app như token).
  static final Map<int, Set<int>> _followsByUser = <int, Set<int>>{};

  /// Xoá toàn bộ theo dõi mock — dùng trong `setUp` của test widget để các
  /// test không dồn dữ liệu của nhau (state là static, cùng một user id).
  /// (Cố ý không dùng `@visibleForTesting` để `dart run tool/check_real_api.dart`
  /// vẫn chạy được khi import service này.)
  static void resetFollowsForTest() => _followsByUser.clear();

  /// Bắt buộc đăng nhập — giống 401 của backend.
  User _requireLogin() {
    final User? me = _me;
    if (_token == null || me == null) {
      throw const ApiException(
        'Bạn cần đăng nhập để thực hiện thao tác này.',
        statusCode: 401,
      );
    }
    return me;
  }

  @override
  Future<List<Story>> fetchMyFollows() async {
    await _wait();
    final User me = _requireLogin();
    final Set<int> ids = _followsByUser[me.id] ?? <int>{};
    final List<Story> result = <Story>[];
    for (final _MockStory mock in _stories) {
      if (ids.contains(mock.id)) result.add(_toStory(mock));
    }
    return result;
  }

  @override
  Future<void> followStory(int storyId) async {
    await _wait();
    final User me = _requireLogin();
    if (_mockById(storyId) == null) {
      throw const ApiException('Không tìm thấy truyện', statusCode: 404);
    }
    (_followsByUser[me.id] ??= <int>{}).add(storyId);
  }

  @override
  Future<void> unfollowStory(int storyId) async {
    await _wait();
    final User me = _requireLogin();
    if (_mockById(storyId) == null) {
      throw const ApiException('Không tìm thấy truyện', statusCode: 404);
    }
    _followsByUser[me.id]?.remove(storyId);
  }

  // ------------------------- Bình luận (Bước 8) -------------------------

  /// Bình luận theo từng truyện (lưu static để giữ qua các lần mở màn hình
  /// như token / theo dõi). Mới nhất nằm đầu danh sách.
  static Map<int, List<Comment>> _commentsByStory = _seedComments();

  /// Bình luận mẫu: truyện 1 có 1 comment của người khác (test không xoá được).
  static Map<int, List<Comment>> _seedComments() => <int, List<Comment>>{
    1: <Comment>[
      Comment(
        id: 900,
        storyId: 1,
        userId: 900, // người khác — không xoá được (403 như backend)
        userName: 'Lê Minh Anh',
        content: 'Truyện đọc cuốn lắm, mong chương mới!',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ],
  };

  /// Trả bình luận về đúng dữ liệu mẫu — dùng trong `setUp` của test widget
  /// để các test không dồn comment của nhau (state là static).
  /// (Cố ý không dùng `@visibleForTesting` của Flutter để `dart run`
  /// tool/check_real_api.dart vẫn chạy được khi import service này.)
  static void resetCommentsForTest() {
    _commentsByStory = _seedComments();
    _nextCommentId = 1000;
  }

  static int _nextCommentId = 1000;

  @override
  Future<List<Comment>> fetchComments(int storyId) async {
    await _wait();
    if (_mockById(storyId) == null) {
      throw const ApiException('Không tìm thấy truyện', statusCode: 404);
    }
    return List<Comment>.of(_commentsByStory[storyId] ?? const <Comment>[]);
  }

  @override
  Future<Comment> addComment(
    int storyId,
    String content, {
    int? chapterId,
  }) async {
    await _wait();
    final User me = _requireLogin();
    final _MockStory? mock = _mockById(storyId);
    if (mock == null) {
      throw const ApiException('Không tìm thấy truyện', statusCode: 404);
    }
    final String text = content.trim();
    if (text.isEmpty) {
      throw const ApiException(
        'Nội dung bình luận không được để trống',
        statusCode: 400,
      );
    }
    // chapterId của mock = storyId * 1000 + index — kiểm tra có thuộc truyện không
    if (chapterId != null &&
        (chapterId ~/ 1000 != storyId ||
            chapterId % 1000 < 1 ||
            chapterId % 1000 > mock.chapterCount)) {
      throw const ApiException(
        'Chương không thuộc truyện này',
        statusCode: 400,
      );
    }
    final Comment comment = Comment(
      id: _nextCommentId++,
      storyId: storyId,
      chapterId: chapterId,
      userId: me.id,
      userName: me.name,
      content: text,
      createdAt: DateTime.now(),
    );
    (_commentsByStory[storyId] ??= <Comment>[]).insert(0, comment);
    return comment;
  }

  @override
  Future<void> deleteComment(int commentId) async {
    await _wait();
    final User me = _requireLogin();
    for (final List<Comment> list in _commentsByStory.values) {
      final int index = list.indexWhere((Comment c) => c.id == commentId);
      if (index >= 0) {
        if (list[index].userId != me.id) {
          throw const ApiException(
            'Bạn chỉ xoá được bình luận của mình',
            statusCode: 403,
          );
        }
        list.removeAt(index);
        return;
      }
    }
    throw const ApiException('Không tìm thấy bình luận', statusCode: 404);
  }

  // ------------------------- Đăng truyện — CRUD (Bước 9) -------------------------

  /// Chương đã thao tác CRUD theo từng truyện. Khi chưa có thì mock vẫn sinh
  /// chương procedural như cũ; khi cần sửa/xoá thì "materialize" từ bản mẫu.
  static Map<int, List<Chapter>> _chaptersByStory = <int, List<Chapter>>{};

  /// Id chương do người dùng tạo (không trùng id quy ước storyId*1000+index).
  static int _nextChapterId = 5000000;

  // ------------------------- Nhập truyện từ link (Bước 10) ------------------

  /// Import job mock — state static, reset bằng [resetImportsForTest].
  static Map<int, _MockImportJob> _importJobs = <int, _MockImportJob>{};
  static int _nextImportJobId = 1;

  /// Xoá toàn bộ import job mock — dùng trong `setUp` của test widget.
  static void resetImportsForTest() {
    _importJobs = <int, _MockImportJob>{};
    _nextImportJobId = 1;
  }

  /// Nguồn mà mock "hỗ trợ" — khớp adapter registry của backend.
  static bool _supportedSource(String url) {
    final String host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return const <String>[
      'qidian.com',
      'demo.vietread.local',
    ].any((String h) => host == h || host.endsWith('.$h'));
  }

  /// Tạo truyện nhập (nháp, 3 chương đã dịch) — mô phỏng kết quả worker
  /// backend: cào → dịch → lưu Chapters(Content = bản dịch) → Done.
  static int _createImportedStory(User user, String sourceUrl) {
    final int storyId = _nextStoryId++;
    _stories.insert(
      0,
      _MockStory(
        id: storyId,
        title: 'Đường Qingyun',
        author: user.name,
        authorId: user.id,
        genres: const <String>['Tiên Hiệp'],
        status: 'ongoing',
        rating: 0,
        chapterCount: 3,
        updatedAgo: Duration.zero,
        hot: 0,
        description:
            'Một thiếu niên bước lên con đường tu hành, trải qua gió mưa, '
            'cuối cùng trở thành một đời tông sư.',
        isDraft: true,
      ),
    );
    _chaptersByStory[storyId] = <Chapter>[
      for (int i = 1; i <= 3; i++)
        Chapter(
          id: _nextChapterId++,
          storyId: storyId,
          index: i,
          title:
              'Chương $i: ${_chapterTitles[(i - 1) % _chapterTitles.length]}',
          content:
              'Chương $i — nội dung đã dịch sang tiếng Việt từ nguồn nước ngoài.\n\n'
              '(Nội dung mẫu của MockApiService cho truyện nhập từ link — Bước 10; '
              'nguồn: $sourceUrl.)',
        ),
    ];
    return storyId;
  }

  /// Tìm truyện hoặc ném 404 như backend.
  _MockStory _storyOrThrow(int storyId) {
    final _MockStory? mock = _mockById(storyId);
    if (mock == null) {
      throw const ApiException('Không tìm thấy truyện', statusCode: 404);
    }
    return mock;
  }

  /// Bắt buộc đăng nhập + chỉ tác giả được thao tác (403 như backend).
  void _requireOwner(_MockStory mock) {
    final User me = _requireLogin();
    if (mock.authorId != me.id) {
      throw const ApiException(
        'Bạn không có quyền thao tác trên truyện này',
        statusCode: 403,
      );
    }
  }

  /// Truyện nháp chỉ chủ nhân xem được — người khác/khách → 404 (backend).
  void _requireViewable(_MockStory mock) {
    if (!mock.isDraft) return;
    if (_me == null || mock.authorId != _me!.id) {
      throw const ApiException('Không tìm thấy truyện', statusCode: 404);
    }
  }

  /// Chuỗi rỗng / toàn khoảng trắng → null; cắt khoảng trắng hai đầu.
  static String? _nullIfEmpty(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Làm sạch danh sách thể loại — giống backend: bỏ rỗng, trùng (không phân biệt hoa thường).
  static List<String> _cleanGenres(List<String> genres) {
    final List<String> cleaned = <String>[];
    final Set<String> seen = <String>{};
    for (final String item in genres) {
      final String name = item.trim();
      if (name.isNotEmpty && seen.add(name.toLowerCase())) cleaned.add(name);
    }
    return cleaned;
  }

  @override
  Future<List<Story>> fetchMyStories() async {
    await _wait();
    final User me = _requireLogin(); // chưa đăng nhập → 401 như backend
    final List<_MockStory> mine =
        _stories.where((_MockStory s) => s.authorId == me.id).toList()..sort(
          (_MockStory a, _MockStory b) => a.updatedAgo.compareTo(b.updatedAgo),
        ); // updatedAgo nhỏ nhất = mới cập nhật
    return mine.map(_toStory).toList(growable: false);
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
    await _wait();
    final User me = _requireLogin();
    final String cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const ApiException(
        'Tên truyện không được để trống',
        statusCode: 400,
      );
    }
    if (status != 'ongoing' && status != 'completed') {
      throw const ApiException(
        "status phải là 'ongoing' hoặc 'completed'",
        statusCode: 400,
      );
    }
    final _MockStory mock = _MockStory(
      id: _nextStoryId++,
      title: cleanTitle,
      author: me.name,
      authorId: me.id,
      genres: _cleanGenres(genres),
      status: status,
      rating: 0,
      chapterCount: 0,
      updatedAgo: Duration.zero,
      hot: 0,
      description: _nullIfEmpty(description),
      coverUrl: _nullIfEmpty(coverUrl),
      isDraft: isDraft,
    );
    _stories.insert(0, mock);
    return _toStory(mock);
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
    await _wait();
    final _MockStory mock = _storyOrThrow(storyId);
    _requireOwner(mock);
    if (title != null) {
      final String cleanTitle = title.trim();
      if (cleanTitle.isEmpty) {
        throw const ApiException(
          'Tên truyện không được để trống',
          statusCode: 400,
        );
      }
      mock.title = cleanTitle;
    }
    if (description != null) mock.description = _nullIfEmpty(description);
    if (coverUrl != null) mock.coverUrl = _nullIfEmpty(coverUrl);
    if (status != null) {
      if (status != 'ongoing' && status != 'completed') {
        throw const ApiException(
          "status phải là 'ongoing' hoặc 'completed'",
          statusCode: 400,
        );
      }
      mock.status = status;
    }
    if (genres != null) mock.genres = _cleanGenres(genres);
    if (isDraft != null) mock.isDraft = isDraft;
    mock.updatedAgo = Duration.zero;
    return _toStory(mock);
  }

  @override
  Future<void> deleteStory(int storyId) async {
    await _wait();
    final _MockStory mock = _storyOrThrow(storyId);
    _requireOwner(mock);
    _stories.remove(mock);
    _chaptersByStory.remove(storyId);
    // ON DELETE CASCADE như backend: chương, bình luận, theo dõi đều theo chân.
    _commentsByStory.remove(storyId);
    for (final Set<int> ids in _followsByUser.values) {
      ids.remove(storyId);
    }
  }

  /// Chương của truyện đã thao tác CRUD — chưa có thì sinh từ bản mẫu.
  List<Chapter> _materializeChapters(_MockStory mock) {
    return _chaptersByStory.putIfAbsent(mock.id, () {
      return List<Chapter>.generate(mock.chapterCount, (int i) {
        final int index = i + 1;
        return Chapter(
          id: chapterIdOf(mock.id, index),
          storyId: mock.id,
          index: index,
          title: 'Chương $index: ${_chapterTitles[i % _chapterTitles.length]}',
          content: _mockContent(mock, index),
        );
      });
    });
  }

  /// Tìm chương theo id bất kỳ trong các bản đã materialize.
  Chapter? _findCustomChapter(int chapterId) {
    for (final List<Chapter> list in _chaptersByStory.values) {
      for (final Chapter c in list) {
        if (c.id == chapterId) return c;
      }
    }
    return null;
  }

  /// Tìm chương để sửa/xoá: chưa materialize thì sinh từ id quy ước
  /// (storyId * 1000 + index) rồi giữ lại trong [_chaptersByStory].
  Chapter _resolveChapter(int chapterId) {
    final Chapter? found = _findCustomChapter(chapterId);
    if (found != null) return found;
    final int storyId = chapterId ~/ 1000;
    final int index = chapterId % 1000;
    final _MockStory? mock = _mockById(storyId);
    if (mock != null && index >= 1) {
      for (final Chapter c in _materializeChapters(mock)) {
        if (c.id == chapterId) return c;
      }
    }
    throw const ApiException('Không tìm thấy chương', statusCode: 404);
  }

  @override
  Future<Chapter> createChapter(
    int storyId, {
    required String title,
    required String content,
    int? index,
  }) async {
    await _wait();
    final _MockStory mock = _storyOrThrow(storyId);
    _requireOwner(mock);
    final String cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const ApiException(
        'Tên chương không được để trống',
        statusCode: 400,
      );
    }
    if (content.trim().isEmpty) {
      throw const ApiException(
        'Nội dung chương không được để trống',
        statusCode: 400,
      );
    }
    final List<Chapter> chapters = _materializeChapters(mock);
    final int newIndex;
    if (index == null) {
      // Tự đánh số tiếp như backend: max + 1 (trống → 1).
      newIndex = chapters.isEmpty
          ? 1
          : chapters.map((Chapter c) => c.index).reduce(max) + 1;
    } else {
      if (index < 1) {
        throw const ApiException(
          'index phải là số nguyên >= 1',
          statusCode: 400,
        );
      }
      if (chapters.any((Chapter c) => c.index == index)) {
        throw ApiException('Chương số $index đã tồn tại', statusCode: 400);
      }
      newIndex = index;
    }
    final Chapter chapter = Chapter(
      id: _nextChapterId++,
      storyId: storyId,
      index: newIndex,
      title: cleanTitle,
      // Chương mới: áp quy tắc ApplyToFuture của truyện (như backend).
      content: _applyGlossary(storyId, content),
    );
    chapters.add(chapter);
    mock.chapterCount = chapters.length;
    mock.updatedAgo = Duration.zero; // backend cũng bump UpdatedAt
    return chapter;
  }

  @override
  Future<Chapter> updateChapter(
    int chapterId, {
    String? title,
    String? content,
    int? index,
  }) async {
    await _wait();
    final Chapter found = _resolveChapter(chapterId);
    final _MockStory mock = _storyOrThrow(found.storyId);
    _requireOwner(mock);

    String newTitle = found.title;
    String newContent = found.content;
    int? newIndex = index;
    if (title != null) {
      final String cleanTitle = title.trim();
      if (cleanTitle.isEmpty) {
        throw const ApiException(
          'Tên chương không được để trống',
          statusCode: 400,
        );
      }
      newTitle = cleanTitle;
    }
    if (content != null) {
      if (content.trim().isEmpty) {
        throw const ApiException(
          'Nội dung chương không được để trống',
          statusCode: 400,
        );
      }
      newContent = content;
    }
    if (newIndex != null) {
      if (newIndex < 1) {
        throw const ApiException(
          'index phải là số nguyên >= 1',
          statusCode: 400,
        );
      }
      final List<Chapter> siblings = _chaptersByStory[found.storyId]!;
      if (siblings.any((Chapter c) => c != found && c.index == newIndex)) {
        throw ApiException('Chương số $newIndex đã tồn tại', statusCode: 400);
      }
    } else {
      newIndex = found.index;
    }

    final Chapter updated = Chapter(
      id: found.id, // id giữ nguyên như backend
      storyId: found.storyId,
      index: newIndex,
      title: newTitle,
      content: newContent,
    );
    final List<Chapter> siblings = _chaptersByStory[found.storyId]!;
    siblings[siblings.indexOf(found)] = updated;
    mock.updatedAgo = Duration.zero;
    return updated;
  }

  @override
  Future<void> deleteChapter(int chapterId) async {
    await _wait();
    final Chapter found = _resolveChapter(chapterId);
    final _MockStory mock = _storyOrThrow(found.storyId);
    _requireOwner(mock);
    final List<Chapter> siblings = _chaptersByStory[found.storyId]!;
    siblings.remove(found);
    mock.chapterCount = siblings.length;
    mock.updatedAgo = Duration.zero;
  }

  // ------------------------- Nhập truyện từ link (Bước 10) ------------------

  @override
  Future<int> startImport({
    required String sourceUrl,
    String targetLang = 'vi',
  }) async {
    await _wait();
    final User me = _requireLogin(); // chưa đăng nhập → 401 như backend
    final String url = sourceUrl.trim();
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const ApiException(
        'sourceUrl không hợp lệ — cần link http(s) đầy đủ',
        statusCode: 400,
      );
    }
    if (targetLang != 'vi') {
      throw const ApiException(
        "targetLang chưa được hỗ trợ (hiện chỉ có 'vi' — Tiếng Việt)",
        statusCode: 400,
      );
    }
    final int id = _nextImportJobId++;
    _importJobs[id] = _MockImportJob(
      id: id,
      sourceUrl: url,
      targetLang: targetLang,
      user: me,
    );
    return id;
  }

  @override
  Future<ImportJob> fetchImportJob(int jobId) async {
    await _wait();
    final User me = _requireLogin();
    final _MockImportJob? job = _importJobs[jobId];
    if (job == null || job.user.id != me.id) {
      throw const ApiException('Không tìm thấy import job', statusCode: 404);
    }
    job.advance(); // mô phỏng worker chạy nền giữa 2 lần poll của app
    return job.toImportJob();
  }

  // ---------------- Thêm chương vào truyện đã có (link / dán văn bản) ------

  /// SourceBookId / SourceChapterId giả lập — khớp cột DB của backend
  /// (Stories.SourceBookId, Chapters.SourceChapterId).
  static Map<int, String> _sourceBookByStory = <int, String>{};

  /// storyId → (sourceChapterId → số chương) — để báo trùng 409 như backend.
  static Map<int, Map<String, int>> _sourceChaptersByStory =
      <int, Map<String, int>>{};

  /// (bookId, chapterId) từ link chương Qidian — cùng regex với backend.
  static final RegExp _qidianChapterRe = RegExp(r'/chapter/(\d+)/(\d+)');
  static final RegExp _qidianLegacyRe = RegExp(r'/book/(\d+)/(\d+)\.html$');

  static bool _isQidianHost(String host) =>
      host == 'qidian.com' || host.endsWith('.qidian.com');

  /// Số chương của các chương đang có (chưa materialize → sinh 1..chapterCount).
  static Iterable<Chapter> _existingChapters(_MockStory mock) =>
      _chaptersByStory[mock.id] ??
      List<Chapter>.generate(mock.chapterCount, (int i) {
        return Chapter(
          id: chapterIdOf(mock.id, i + 1),
          storyId: mock.id,
          index: i + 1,
          title: '',
          content: '',
        );
      });

  /// Số chương mới: chapterNo → MAX+1 (trống → 1); trùng → 409 như backend.
  static int _nextIndexFor(_MockStory mock, int? chapterNo) {
    if (chapterNo != null) {
      if (chapterNo < 1) {
        throw const ApiException(
          'Số chương phải là số nguyên ≥ 1',
          statusCode: 400,
        );
      }
      if (_existingChapters(mock).any((Chapter c) => c.index == chapterNo)) {
        throw ApiException(
          'Chương số $chapterNo đã tồn tại trong truyện',
          statusCode: 409,
        );
      }
      return chapterNo;
    }
    final Iterable<Chapter> chapters = _existingChapters(mock);
    if (chapters.isEmpty) return 1;
    return chapters.map((Chapter c) => c.index).reduce(max) + 1;
  }

  /// Thêm chương vào danh sách materialize + cập nhật truyện (giống backend).
  Chapter _appendChapter(
    _MockStory mock,
    int index,
    String title,
    String content,
  ) {
    final Chapter chapter = Chapter(
      id: _nextChapterId++,
      storyId: mock.id,
      index: index,
      title: title,
      content: content,
    );
    _materializeChapters(mock).add(chapter);
    mock.chapterCount = _chaptersByStory[mock.id]!.length;
    mock.updatedAgo = Duration.zero;
    return chapter;
  }

  @override
  Future<Chapter> importChapterFromUrl(
    int storyId, {
    required String chapterUrl,
    int? chapterNo,
    String? title,
  }) async {
    await _wait();
    final _MockStory mock = _storyOrThrow(storyId);
    _requireOwner(mock);

    final String url = chapterUrl.trim();
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const ApiException(
        'Link không hợp lệ — cần link http(s) đầy đủ',
        statusCode: 400,
      );
    }
    if (!_isQidianHost(uri.host.toLowerCase())) {
      throw const ApiException(
        'Chỉ hỗ trợ thêm chương từ Qidian',
        statusCode: 400,
      );
    }
    // Giả lập lỗi nguồn: link có “vip” → chương trả phí (không vượt rào).
    if (uri.path.contains('vip')) {
      throw const ApiException(
        'Nội dung chương này là trả phí (VIP) của Qidian — chỉ đọc được đoạn '
        'mở đầu, cần đăng nhập/mua điểm để lấy trọn chương',
        statusCode: 400,
      );
    }
    final RegExpMatch? m =
        _qidianChapterRe.firstMatch(uri.path) ??
        _qidianLegacyRe.firstMatch(uri.path);
    if (m == null) {
      throw const ApiException(
        'Link không đúng định dạng chương Qidian',
        statusCode: 400,
      );
    }
    final String bookId = m.group(1)!;
    final String chapterId = m.group(2)!;

    // Chống nhầm truyện.
    final String? storyBook = _sourceBookByStory[storyId];
    if (storyBook != null && storyBook != bookId) {
      throw const ApiException('Link này thuộc truyện khác', statusCode: 400);
    }
    // Chống trùng chương.
    final int? existingIndex = _sourceChaptersByStory[storyId]?[chapterId];
    if (existingIndex != null) {
      throw ApiException(
        'Chương này đã được nhập (chương số $existingIndex)',
        statusCode: 409,
      );
    }

    final int index = _nextIndexFor(mock, chapterNo);
    final Chapter chapter = _appendChapter(
      mock,
      index,
      (title?.trim().isNotEmpty ?? false) ? title!.trim() : 'Chương $index',
      // Chương mới: áp quy tắc ApplyToFuture của truyện (như backend).
      _applyGlossary(
        storyId,
        'Nội dung đã cào và dịch từ Qidian (mô phỏng) — $url',
      ),
    );
    _sourceBookByStory[storyId] = bookId;
    (_sourceChaptersByStory[storyId] ??= <String, int>{})[chapterId] = index;
    return chapter;
  }

  @override
  Future<Chapter> importChapterFromText(
    int storyId, {
    required String text,
    required String sourceLang,
    int? chapterNo,
    String? title,
  }) async {
    await _wait();
    final _MockStory mock = _storyOrThrow(storyId);
    _requireOwner(mock);

    if (text.trim().isEmpty) {
      throw const ApiException(
        'Nội dung chương không được để trống',
        statusCode: 400,
      );
    }
    if (text.length > 100000) {
      throw const ApiException(
        'Nội dung chương tối đa 100.000 ký tự',
        statusCode: 400,
      );
    }
    if (sourceLang != 'zh' && sourceLang != 'vi') {
      throw const ApiException(
        "sourceLang phải là 'zh' (Trung) hoặc 'vi' (Việt)",
        statusCode: 400,
      );
    }

    final String firstLine = text
        .split('\n')
        .firstWhere((String l) => l.trim().isNotEmpty, orElse: () => '')
        .trim();
    final int index = _nextIndexFor(mock, chapterNo);
    final String? cleanTitle = (title?.trim().isNotEmpty ?? false)
        ? title!.trim()
        : null;
    final String chapterTitle =
        cleanTitle ??
        (firstLine.length <= 120 && firstLine.isNotEmpty
            ? firstLine
            : 'Chương $index');
    // sourceLang=vi: lưu nguyên; zh: “dịch” (mô phỏng) rồi giữ bản gốc.
    // Bản dịch có marker nhiều nghĩa như backend khi mark_alternatives=true.
    final bool isZh = sourceLang == 'zh';
    final String content = isZh
        ? 'Bản dịch (mô phỏng): $text\n'
              'Chỗ cần chọn nghĩa: {nghĩa một|nghĩa hai} và {Lý Minh|Lý Meanh}.'
        : text;
    final Chapter chapter = _appendChapter(
      mock,
      index,
      chapterTitle,
      _applyGlossary(storyId, content), // chương mới: áp quy tắc ApplyToFuture
    );
    if (isZh) _originalByChapter[chapter.id] = text; // bản gốc cho retranslate
    return chapter;
  }

  // ------------------------- Sửa bản dịch: marker + thay thế ----------------

  /// Bản gốc (chưa dịch) của chương nhập bằng văn bản — cho `retranslate`.
  static Map<int, String> _originalByChapter = <int, String>{};

  /// Quy tắc "Tìm & thay thế" đã lưu theo truyện (bảng `StoryGlossary`).
  static Map<int, List<GlossaryRule>> _glossaryByStory =
      <int, List<GlossaryRule>>{};

  /// Batch thay thế gần nhất của mỗi truyện (bảng `ChapterRevisions`) —
  /// batch mới xoá batch cũ, dùng cho `undoReplace`.
  static Map<int, _MockReplaceBatch> _replaceBatches =
      <int, _MockReplaceBatch>{};

  static int _nextGlossaryId = 1;
  static int _nextReplaceBatchId = 1;

  /// Ý nghĩa đã chọn ("luôn dùng") / từ "không hỏi lại" THEO TRUYỆN —
  /// bảng `StoryWordChoices` / `StoryIgnoredWords`.
  static Map<int, List<WordChoice>> _wordChoicesByStory =
      <int, List<WordChoice>>{};
  static Map<int, List<IgnoredWord>> _ignoredWordsByStory =
      <int, List<IgnoredWord>>{};
  static int _nextWordChoiceId = 1;
  static int _nextIgnoredWordId = 1;

  /// markLevel của lần `retranslateChapter` gần nhất — widget test kiểm tra
  /// mức gợi ý người dùng chọn có được gửi lên không.
  static String? lastRetranslateMarkLevel;

  static const Set<String> _markLevels = <String>{'low', 'medium', 'high'};

  /// Xoá toàn bộ trạng thái marker/thay thế — `resetStoriesForTest` gọi kèm.
  static void resetGlossaryForTest() {
    _originalByChapter = <int, String>{};
    _glossaryByStory = <int, List<GlossaryRule>>{};
    _replaceBatches = <int, _MockReplaceBatch>{};
    _nextGlossaryId = 1;
    _nextReplaceBatchId = 1;
    _wordChoicesByStory = <int, List<WordChoice>>{};
    _ignoredWordsByStory = <int, List<IgnoredWord>>{};
    _nextWordChoiceId = 1;
    _nextIgnoredWordId = 1;
    lastRetranslateMarkLevel = null;
  }

  /// Regex cho một quy tắc — khớp [buildRegex] của backend (`glossary.py`).
  static RegExp _rulePattern(String find, bool matchCase, bool wholeWord) =>
      RegExp(
        wholeWord
            ? '(?<!\\w)${RegExp.escape(find)}(?!\\w)'
            : RegExp.escape(find),
        caseSensitive: matchCase,
      );

  /// Số chỗ khớp trong [text].
  static int _countMatches(String text, RegExp rx) =>
      rx.allMatches(text).length;

  /// Áp mọi quy tắc ApplyToFuture của truyện lên bản dịch chương MỚI (như backend).
  static String _applyGlossary(int storyId, String text) {
    for (final GlossaryRule rule
        in _glossaryByStory[storyId] ?? const <GlossaryRule>[]) {
      if (!rule.applyToFuture) continue;
      text = text.replaceAll(
        _rulePattern(rule.findText, rule.matchCase, rule.wholeWord),
        rule.replaceText,
      );
    }
    return text;
  }

  @override
  Future<String> retranslateChapter(int chapterId, {String? markLevel}) async {
    await _wait();
    final Chapter chapter = _resolveChapter(chapterId);
    _requireOwner(_storyOrThrow(chapter.storyId));
    final String? original = _originalByChapter[chapter.id];
    if (original == null || original.trim().isEmpty) {
      throw const ApiException(
        'Chương này không có bản gốc để dịch lại',
        statusCode: 400,
      );
    }
    if (markLevel != null && !_markLevels.contains(markLevel)) {
      throw const ApiException(
        "markLevel phải là 'low', 'medium' hoặc 'high'",
        statusCode: 400,
      );
    }
    lastRetranslateMarkLevel = markLevel;
    // “Dịch lại” mô phỏng — marker chỉ chứa NGHĨA VIỆT như backend (`{a|b}`),
    // dùng từ điển cá nhân (giống names.txt), rồi áp nghĩa đã chọn /
    // "không hỏi lại" RIÊNG CỦA TRUYỆN + trần marker theo mức gợi ý.
    final String content = _applyGlossary(
      chapter.storyId,
      'Bản dịch lại (mô phỏng):\n'
          'Thiếu niên {nghĩa một|nghĩa hai|nghĩa ba} đứng trên đỉnh núi.\n'
          'Đây là {Lý Minh|Lý Meanh} — chỗ này cần chọn nghĩa.',
    );
    return _applyStoryWords(
      chapter.storyId,
      content,
      cap: markLevel == 'low'
          ? 15
          : markLevel == 'medium'
          ? 40
          : null,
    );
  }

  /// Danh tính quy tắc theo marker — KHỚP cách backend tra ngược khóa:
  /// khóa cũ (nếu client gửi) hoặc danh sách nghĩa Việt đã chuẩn hóa.
  /// Trả `null` khi thiếu cả hai (backend trả 400).
  static String? _identity(String? sourceKey, List<String>? meanings) {
    if (sourceKey != null && sourceKey.isNotEmpty) return sourceKey;
    final Set<String> clean = <String>{
      for (final String m in meanings ?? const <String>[])
        if (m.trim().isNotEmpty && !hasCjk(m.trim())) m.trim(),
    };
    if (clean.isEmpty) return null;
    return clean.take(6).join('|');
  }

  /// Phản hồi POST kèm [affectedIds] (mock ghi 1 khóa → id duy nhất).
  static WordChoice _withIds(WordChoice row, List<int> ids) => WordChoice(
    id: row.id,
    sourceKey: row.sourceKey,
    chosenText: row.chosenText,
    createdAt: row.createdAt,
    affectedIds: ids,
  );

  static IgnoredWord _ignoreWithIds(IgnoredWord row, List<int> ids) =>
      IgnoredWord(
        id: row.id,
        sourceKey: row.sourceKey,
        createdAt: row.createdAt,
        affectedIds: ids,
      );

  /// Áp “luôn dùng nghĩa” + “không hỏi lại” của truyện lên văn bản có marker,
  /// rồi cắt về trần [cap] của mức gợi ý (marker vượt trần lấy nghĩa đầu).
  static String _applyStoryWords(int storyId, String text, {int? cap}) {
    final Map<String, String> choices = <String, String>{
      for (final WordChoice c
          in _wordChoicesByStory[storyId] ?? const <WordChoice>[])
        c.sourceKey: c.chosenText,
    };
    final Set<String> skips = <String>{
      for (final IgnoredWord w
          in _ignoredWordsByStory[storyId] ?? const <IgnoredWord>[])
        w.sourceKey,
    };
    int seen = 0;
    final StringBuffer buf = StringBuffer();
    int pos = 0;
    for (final Marker marker in parseMarkers(text)) {
      // Danh tính: khóa cũ (dữ liệu cũ) hoặc chính dãy nghĩa của marker
      // (marker mới không còn chữ Trung) — như backend tra ngược khóa.
      final String key = marker.key ?? marker.meanings.join('|');
      String? replacement;
      if (choices.containsKey(key)) {
        replacement = choices[key];
      } else if (skips.contains(key)) {
        replacement = marker.first;
      } else if (cap != null && seen >= cap) {
        replacement = marker.first; // vượt trần mức gợi ý → lấy nghĩa đầu
      }
      if (replacement == null) {
        seen += 1;
        continue; // giữ nguyên marker
      }
      buf.write(text.substring(pos, marker.start));
      buf.write(replacement);
      pos = marker.end;
    }
    if (buf.isEmpty) return text;
    buf.write(text.substring(pos));
    return buf.toString();
  }

  // ------------------------- Gợi ý nhiều nghĩa theo truyện ----------------

  @override
  Future<List<WordChoice>> fetchWordChoices(int storyId) async {
    await _wait();
    _requireOwner(_storyOrThrow(storyId));
    return List<WordChoice>.unmodifiable(
      _wordChoicesByStory[storyId] ?? const <WordChoice>[],
    );
  }

  @override
  Future<WordChoice> saveWordChoice(
    int storyId, {
    String? sourceKey,
    required String chosenText,
    List<String>? meanings,
  }) async {
    await _wait();
    _requireOwner(_storyOrThrow(storyId));
    final String? identity = _identity(sourceKey, meanings);
    if (identity == null) {
      throw const ApiException(
        'Cần gửi sourceKey hoặc meanings',
        statusCode: 400,
      );
    }
    final List<WordChoice> list = _wordChoicesByStory.putIfAbsent(
      storyId,
      () => <WordChoice>[],
    );
    final int i = list.indexWhere((WordChoice c) => c.sourceKey == identity);
    if (i >= 0) {
      final WordChoice old = list[i];
      list[i] = WordChoice(
        id: old.id,
        sourceKey: old.sourceKey,
        chosenText: chosenText,
        createdAt: old.createdAt,
      );
      return _withIds(list[i], <int>[old.id]);
    }
    final WordChoice choice = WordChoice(
      id: _nextWordChoiceId++,
      sourceKey: identity,
      chosenText: chosenText,
      createdAt: DateTime.now(),
    );
    list.insert(0, choice);
    return _withIds(choice, <int>[choice.id]);
  }

  @override
  Future<void> deleteWordChoice(int storyId, int choiceId) async {
    await _wait();
    _requireOwner(_storyOrThrow(storyId));
    final List<WordChoice> list =
        _wordChoicesByStory[storyId] ?? const <WordChoice>[];
    final int i = list.indexWhere((WordChoice c) => c.id == choiceId);
    if (i < 0) {
      throw const ApiException('Không tìm thấy nghĩa đã lưu', statusCode: 404);
    }
    list.removeAt(i);
  }

  @override
  Future<List<IgnoredWord>> fetchIgnoredWords(int storyId) async {
    await _wait();
    _requireOwner(_storyOrThrow(storyId));
    return List<IgnoredWord>.unmodifiable(
      _ignoredWordsByStory[storyId] ?? const <IgnoredWord>[],
    );
  }

  @override
  Future<IgnoredWord> ignoreWord(
    int storyId, {
    String? sourceKey,
    List<String>? meanings,
  }) async {
    await _wait();
    _requireOwner(_storyOrThrow(storyId));
    final String? identity = _identity(sourceKey, meanings);
    if (identity == null) {
      throw const ApiException(
        'Cần gửi sourceKey hoặc meanings',
        statusCode: 400,
      );
    }
    final List<IgnoredWord> list = _ignoredWordsByStory.putIfAbsent(
      storyId,
      () => <IgnoredWord>[],
    );
    final int i = list.indexWhere((IgnoredWord w) => w.sourceKey == identity);
    if (i >= 0) {
      return _ignoreWithIds(list[i], <int>[
        list[i].id,
      ]); // idempotent như backend
    }
    final IgnoredWord word = IgnoredWord(
      id: _nextIgnoredWordId++,
      sourceKey: identity,
      createdAt: DateTime.now(),
    );
    list.insert(0, word);
    return _ignoreWithIds(word, <int>[word.id]);
  }

  @override
  Future<void> deleteIgnoredWord(int storyId, int wordId) async {
    await _wait();
    _requireOwner(_storyOrThrow(storyId));
    final List<IgnoredWord> list =
        _ignoredWordsByStory[storyId] ?? const <IgnoredWord>[];
    final int i = list.indexWhere((IgnoredWord w) => w.id == wordId);
    if (i < 0) {
      throw const ApiException(
        'Không tìm thấy từ trong danh sách',
        statusCode: 404,
      );
    }
    list.removeAt(i);
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
    await _wait();
    final _MockStory mock = _storyOrThrow(storyId);
    _requireOwner(mock);
    if (find.trim().isEmpty) {
      throw const ApiException(
        'Chuỗi cần tìm không được để trống',
        statusCode: 400,
      );
    }
    if (find.length > 200) {
      throw const ApiException(
        'Chuỗi cần tìm tối đa 200 ký tự',
        statusCode: 400,
      );
    }
    if (find == replace) {
      throw const ApiException(
        'Chuỗi cần tìm và chuỗi thay thế không được giống nhau',
        statusCode: 400,
      );
    }
    final RegExp rx = _rulePattern(find, matchCase, wholeWord);
    final List<Chapter> chapters = _materializeChapters(mock);

    // --- dryRun: chỉ đếm chỗ/chương, không ghi gì ---
    final List<ReplaceChapterHit> hits = <ReplaceChapterHit>[];
    int total = 0;
    for (final Chapter chapter in chapters) {
      final int matches =
          _countMatches(chapter.content, rx) +
          (includeTitles ? _countMatches(chapter.title, rx) : 0);
      if (matches > 0) {
        hits.add(
          ReplaceChapterHit(
            chapterId: chapter.id,
            chapterNo: chapter.index,
            matches: matches,
          ),
        );
        total += matches;
      }
    }
    if (dryRun) {
      return ReplaceResult(dryRun: true, totalMatches: total, chapters: hits);
    }

    // --- Thay thật: snapshot trước batch để undo (1 batch gần nhất/truyện) ---
    final String batchId = 'batch-${_nextReplaceBatchId++}';
    final List<_MockRevision> revisions = <_MockRevision>[];
    final Map<int, String> afterByChapter = <int, String>{};
    final List<ReplaceChapterHit> changedHits = <ReplaceChapterHit>[];
    int changed = 0;
    total = 0;
    for (int i = 0; i < chapters.length; i++) {
      final Chapter chapter = chapters[i];
      final int matches =
          _countMatches(chapter.content, rx) +
          (includeTitles ? _countMatches(chapter.title, rx) : 0);
      if (matches == 0) continue;
      revisions.add(
        _MockRevision(
          chapterId: chapter.id,
          title: chapter.title,
          content: chapter.content,
        ),
      );
      final Chapter updated = Chapter(
        id: chapter.id,
        storyId: chapter.storyId,
        index: chapter.index,
        title: includeTitles
            ? chapter.title.replaceAll(rx, replace)
            : chapter.title,
        content: chapter.content.replaceAll(rx, replace),
      );
      chapters[i] = updated;
      afterByChapter[updated.id] = updated.content;
      changed += 1;
      total += matches;
      changedHits.add(
        ReplaceChapterHit(
          chapterId: chapter.id,
          chapterNo: chapter.index,
          matches: matches,
        ),
      );
    }
    _replaceBatches[storyId] = _MockReplaceBatch(
      batchId: batchId,
      revisions: revisions,
      afterByChapter: afterByChapter,
    );
    if (applyToFuture) {
      final List<GlossaryRule> rules = _glossaryByStory.putIfAbsent(
        storyId,
        () => <GlossaryRule>[],
      );
      rules.add(
        GlossaryRule(
          id: _nextGlossaryId++,
          findText: find,
          replaceText: replace,
          matchCase: matchCase,
          wholeWord: wholeWord,
          applyToFuture: true,
          createdAt: DateTime.now(),
        ),
      );
    }
    return ReplaceResult(
      dryRun: false,
      totalMatches: total,
      chapters: changedHits,
      batchId: batchId,
      chaptersChanged: changed,
    );
  }

  @override
  Future<UndoResult> undoReplace(int storyId) async {
    await _wait();
    final _MockStory mock = _storyOrThrow(storyId);
    _requireOwner(mock);
    final _MockReplaceBatch? batch = _replaceBatches.remove(storyId);
    if (batch == null) {
      throw const ApiException(
        'Chưa có lần thay thế nào để hoàn tác',
        statusCode: 400,
      );
    }
    final List<Chapter> chapters = _chaptersByStory[storyId] ?? <Chapter>[];
    int restored = 0;
    int skipped = 0;
    for (final _MockRevision revision in batch.revisions) {
      final int i = chapters.indexWhere(
        (Chapter c) => c.id == revision.chapterId,
      );
      // Chương bị xoá hoặc đã sửa tiếp sau batch → bỏ qua (như backend).
      if (i < 0 ||
          chapters[i].content != batch.afterByChapter[revision.chapterId]) {
        skipped += 1;
        continue;
      }
      chapters[i] = Chapter(
        id: revision.chapterId,
        storyId: storyId,
        index: chapters[i].index,
        title: revision.title,
        content: revision.content,
      );
      restored += 1;
    }
    final String message =
        'Đã hoàn tác $restored chương'
        '${skipped > 0 ? ' — $skipped chương đã bị sửa sau đó nên bỏ qua' : ''}';
    return UndoResult(message: message, restored: restored, skipped: skipped);
  }

  @override
  Future<List<GlossaryRule>> fetchGlossary(int storyId) async {
    await _wait();
    _requireOwner(_storyOrThrow(storyId));
    return List<GlossaryRule>.unmodifiable(
      _glossaryByStory[storyId] ?? const <GlossaryRule>[],
    );
  }

  @override
  Future<void> deleteGlossaryRule(int storyId, int ruleId) async {
    await _wait();
    _requireOwner(_storyOrThrow(storyId));
    final List<GlossaryRule> rules =
        _glossaryByStory[storyId] ?? const <GlossaryRule>[];
    final int i = rules.indexWhere((GlossaryRule r) => r.id == ruleId);
    if (i < 0) {
      throw const ApiException('Không tìm thấy quy tắc', statusCode: 404);
    }
    rules.removeAt(i);
  }

  /// Nội dung chương mẫu (đủ dấu tiếng Việt) cho bản mock.
  static String _mockContent(_MockStory story, int index) {
    final String subtitle = _chapterTitles[(index - 1) % _chapterTitles.length];
    return '''${story.title} — Chương $index: $subtitle

Trời vừa sáng, sương còn đọng trên ngọn cỏ biên thành. $subtitle là đoạn khiến người đọc nhớ nhất, và ở chương $index này, mọi chuyện bắt đầu chuyển hướng.

Người ngồi bên bếp lửa lặng im rất lâu. Y biết rằng phía sau cánh cửa đá là câu trả lời cho tất cả những gì đã xảy ra từ đầu, nhưng y cũng biết rằng có những sự thật một khi nói ra thì không thể rút lại.

Gió thổi qua thềm đá, cuốn đi vài trang sách cũ. Ở chương tới, cuộc gặp ở chợ đêm sẽ thay đổi mọi kế hoạch đã dựng bao năm.

(Đây là nội dung mẫu của MockApiService — khi tắt cờ useMock, ứng dụng hiển thị nội dung thật từ backend.)''';
  }
}

/// Bản ghi mock, giữ thêm chỉ số `hot` không có trong JSON API.
/// Trường ngoài id/author/authorId có thể đổi khi người dùng CRUD (Bước 9).
class _MockStory {
  _MockStory({
    required this.id,
    required this.title,
    required this.author,
    required this.authorId,
    required this.genres,
    required this.status,
    required this.rating,
    required this.chapterCount,
    required this.updatedAgo,
    required this.hot,
    required this.description,
    this.coverUrl,
    this.isDraft = false,
  });

  final int id;
  String title;
  final String author;
  final int authorId;
  List<String> genres;
  String status;
  final double rating;

  /// Số chương — tăng/giảm khi thêm/xoá chương (Bước 9).
  int chapterCount;

  Duration updatedAgo; // đặt lại Duration.zero khi truyện được sửa
  final int hot;
  String? description;
  String? coverUrl; // ảnh bìa người dùng nhập (null = theo cờ useCoverImages)
  bool isDraft;
}

/// Batch thay thế gần nhất của một truyện — mô phỏng `ChapterRevisions`
/// (chỉ giữ 1 batch gần nhất, batch mới xoá batch cũ).
class _MockReplaceBatch {
  _MockReplaceBatch({
    required this.batchId,
    required this.revisions,
    required this.afterByChapter,
  });

  final String batchId;
  final List<_MockRevision> revisions;

  /// Nội dung MỖI chương sau khi batch thay thế — chương nào bị sửa tiếp
  /// (khác giá trị này) thì undo bỏ qua, giống `UpdatedAt > snapshot` ở backend.
  final Map<int, String> afterByChapter;
}

/// Snapshot một chương TRƯỚC batch thay thế (title + content).
class _MockRevision {
  _MockRevision({
    required this.chapterId,
    required this.title,
    required this.content,
  });

  final int chapterId;
  final String title;
  final String content;
}

/// Import job trong mock — mô phỏng worker backend chạy nền (Bước 10):
/// mỗi lần app poll lại "advance" một bước: Pending → Running (%) → Done/Failed.
class _MockImportJob {
  _MockImportJob({
    required this.id,
    required this.sourceUrl,
    required this.targetLang,
    required this.user,
  });

  final int id;
  final String sourceUrl;
  final String targetLang;
  final User user;

  String status = 'Pending';
  int progress = 0;
  int? storyId;
  String? error;
  int _step = 0;

  /// Một bước xử lý — job đã kết thúc thì giữ nguyên (idempotent).
  void advance() {
    if (status == 'Done' || status == 'Failed') return;
    if (status == 'Pending') {
      status = 'Running';
      progress = 20;
      return;
    }
    _step += 1;
    if (_step >= 2) {
      _finish();
    } else {
      progress = 60;
    }
  }

  /// Xong → tạo truyện nháp + chương; nguồn lạ → Failed kèm lỗi như backend.
  void _finish() {
    if (!MockApiService._supportedSource(sourceUrl)) {
      status = 'Failed';
      final String host = Uri.parse(sourceUrl).host;
      error =
          "Nguồn '$host' chưa được hỗ trợ — hiện chỉ hỗ trợ "
          'Qidian và nguồn demo demo.vietread.local';
      return;
    }
    status = 'Done';
    progress = 100;
    storyId = MockApiService._createImportedStory(user, sourceUrl);
  }

  ImportJob toImportJob() => ImportJob(
    jobId: id,
    status: status,
    progress: progress,
    storyId: storyId,
    error: error,
  );
}
