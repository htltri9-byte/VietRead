import 'dart:math';

import '../models/chapter.dart';
import '../models/comment.dart';
import '../models/genre.dart';
import '../models/import_job.dart';
import '../models/story.dart';
import '../models/user.dart';
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
    _nextStoryId = 9;
    _nextChapterId = 5000000;
  }

  Story _toStory(_MockStory mock) => Story(
    id: mock.id,
    title: mock.title,
    author: mock.author,
    authorId: mock.authorId,
    // Ảnh bìa người dùng nhập luôn thắng ảnh picsum ngẫu nhiên.
    coverUrl: mock.coverUrl ??
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
  Future<Chapter> fetchChapter(int chapterId) async {
    await _wait();
    // Ưu tiên chương đã thao tác CRUD (id do mock cấp, không quy ước).
    final Chapter? custom = _findCustomChapter(chapterId);
    if (custom != null) {
      _requireViewable(_storyOrThrow(custom.storyId));
      return custom;
    }
    // Mock: id chương = storyId * 1000 + index (xem chapterIdOf)
    final int storyId = chapterId ~/ 1000;
    final int index = chapterId % 1000;
    final _MockStory? mock = _mockById(storyId);
    if (mock == null || index < 1 || index > mock.chapterCount) {
      throw const ApiException('Không tìm thấy chương');
    }
    final String title =
        'Chương $index: ${_chapterTitles[(index - 1) % _chapterTitles.length]}';
    return Chapter(
      id: chapterId,
      storyId: storyId,
      index: index,
      title: title,
      content: _mockContent(mock, index),
    );
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
    return List<Comment>.of(
      _commentsByStory[storyId] ?? const <Comment>[],
    );
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
      throw const ApiException('Chương không thuộc truyện này', statusCode: 400);
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
      'faloo.com',
      'fanqie.com.cn',
      'fanqienovel.com',
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
          title: 'Chương $i: ${_chapterTitles[(i - 1) % _chapterTitles.length]}',
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
    final List<_MockStory> mine = _stories
        .where((_MockStory s) => s.authorId == me.id)
        .toList()
      ..sort(
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
      throw const ApiException('Tên truyện không được để trống', statusCode: 400);
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
          title:
              'Chương $index: ${_chapterTitles[i % _chapterTitles.length]}',
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
        throw ApiException(
          'Chương số $index đã tồn tại',
          statusCode: 400,
        );
      }
      newIndex = index;
    }
    final Chapter chapter = Chapter(
      id: _nextChapterId++,
      storyId: storyId,
      index: newIndex,
      title: cleanTitle,
      content: content,
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
      if (siblings.any(
        (Chapter c) => c != found && c.index == newIndex,
      )) {
        throw ApiException(
          'Chương số $newIndex đã tồn tại',
          statusCode: 400,
        );
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
          "Nguồn '$host' chưa được hỗ trợ — hiện hỗ trợ "
          'Qidian, B.faloo, Fanqie và nguồn demo demo.vietread.local';
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
