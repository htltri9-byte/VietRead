import 'dart:async';

import 'package:flutter/material.dart';

import '../models/import_job.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/empty_state.dart';
import 'auth_screen.dart';

/// Màn **Nhập truyện từ link** — A3.10 (Bước 10).
///
/// - Dán link nguồn (Qidian hoặc nguồn demo) → chọn ngôn
///   ngữ đích → `POST /imports` tạo job rồi poll `GET /imports/{jobId}`
///   mỗi 1.5 giây cho tới khi `Done` / `Failed` ( Pending / Running / % chương ).
/// - Việc cào + dịch chạy ở **backend** nên quay về màn khác job vẫn tiếp tục.
/// - Khi xong, truyện xuất hiện trong "Truyện của tôi" ở dạng **nháp**.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.api});

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  final TextEditingController _url = TextEditingController();
  String _lang = 'vi';

  /// Job hiện tại (`null` = đang ở form nhập link).
  int? _jobId;
  ImportJob? _job;
  bool _starting = false;
  String? _urlError; // lỗi validate ngay trên ô link
  Object? _pollError; // lỗi khi poll (mất mạng…) → nút "Thử lại"
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _api.setToken(AuthService.instance.session?.token);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _url.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Validate tại chỗ rồi tạo job + bắt đầu poll.
  Future<void> _start() async {
    if (_starting) return;
    final String url = _url.text.trim();
    final Uri? uri = Uri.tryParse(url);
    if (url.isEmpty) {
      setState(() => _urlError = 'Vui lòng dán link truyện');
      return;
    }
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() => _urlError = 'Link không hợp lệ — cần http(s) đầy đủ');
      return;
    }
    setState(() {
      _starting = true;
      _urlError = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final int jobId = await _api.startImport(
        sourceUrl: url,
        targetLang: _lang,
      );
      if (!mounted) return;
      setState(() {
        _jobId = jobId;
        _job = null;
        _pollError = null;
        _starting = false;
      });
      unawaited(_poll());
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      _showMessage(
        e is ApiException ? e.message : 'Không tạo được yêu cầu nhập truyện.',
      );
    }
  }

  /// Hỏi trạng thái job 1 lần; nếu còn Pending/Running thì hẹn 1.5s hỏi tiếp.
  Future<void> _poll() async {
    final int? jobId = _jobId;
    if (jobId == null || !mounted) return;
    try {
      _api.setToken(AuthService.instance.session?.token);
      final ImportJob job = await _api.fetchImportJob(jobId);
      if (!mounted) return;
      setState(() {
        _job = job;
        _pollError = null;
      });
      if (job.isDone || job.isFailed) return; // kết thúc → ngừng poll
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 1500), () {
        unawaited(_poll());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pollError = e); // hiện lỗi + cho phép thử lại
    }
  }

  /// Về lại form nhập link (giữ nguyên link đã dán).
  void _reset() {
    _timer?.cancel();
    setState(() {
      _jobId = null;
      _job = null;
      _pollError = null;
      _urlError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (BuildContext context, _) {
        final bool loggedIn = AuthService.instance.isLoggedIn;
        return Scaffold(
          appBar: AppBar(title: const Text('Nhập truyện từ link')),
          body: loggedIn ? _body() : _loginPrompt(),
        );
      },
    );
  }

  /// Chưa đăng nhập → lời mời + nút Đăng nhập (giống tab Đăng truyện).
  Widget _loginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const EmptyState(
              icon: Icons.link_rounded,
              title: 'Đăng nhập để nhập truyện',
              message: 'Dán link truyện nước ngoài, VietRead tự cào và dịch sang tiếng Việt.',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder: (_) => const AuthScreen()),
                );
                // AnimatedBuilder tự build lại sau khi đăng nhập xong.
              },
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Đăng nhập'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_jobId == null) return _form();
    return _statusView();
  }

  // ------------------------- Form nhập link -------------------------

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Link truyện *',
            hintText: 'https://m.qidian.com/book/123/',
            errorText: _urlError,
          ),
          onSubmitted: (_) => _start(),
          onChanged: (_) {
            if (_urlError != null) setState(() => _urlError = null);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _lang,
          decoration: const InputDecoration(
            labelText: 'Ngôn ngữ đích',
            helperText: 'Nội dung sẽ được dịch sang ngôn ngữ này.',
          ),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(value: 'vi', child: Text('Tiếng Việt')),
          ],
          onChanged: (String? v) => setState(() => _lang = v ?? 'vi'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _starting ? null : _start,
          icon: _starting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_link_rounded, size: 18),
          label: const Text('Bắt đầu nhập'),
        ),
        const SizedBox(height: 12),
        Text(
          'Việc cào và dịch chạy ở máy chủ; truyện nhập về dạng nháp để bạn '
          'chỉnh sửa trước khi đăng. Nguồn demo: demo.vietread.local/book/1',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ------------------------- Theo dõi trạng thái -------------------------

  Widget _statusView() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ImportJob? job = _job;
    final String status = job?.status ?? 'Pending';
    final int progress = job?.progress ?? 0;

    final Color color = switch (status) {
      'Done' => scheme.primary,
      'Failed' => scheme.error,
      'Running' => scheme.secondary,
      _ => scheme.onSurfaceVariant,
    };
    final IconData icon = switch (status) {
      'Done' => Icons.check_circle_rounded,
      'Failed' => Icons.error_outline_rounded,
      'Running' => Icons.autorenew_rounded,
      _ => Icons.hourglass_top_rounded,
    };
    final String label = job?.statusLabel ?? 'Đang chờ';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        // Link nguồn + trạng thái
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _url.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(icon, size: 14, color: color),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$progress%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: job?.progress01,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                ),
                if (status == 'Failed' &&
                    (job?.error?.isNotEmpty ?? false)) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    job!.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
                if (status != 'Done' && status != 'Failed') ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Job chạy trên máy chủ — bạn có thể quay lại sau.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Lỗi poll (mất mạng giữa chừng) → thử lại
        if (_pollError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _pollError is ApiException
                        ? (_pollError as ApiException).message
                        : 'Không kiểm tra được trạng thái job.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
                TextButton(onPressed: _poll, child: const Text('Thử lại')),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Hành động theo trạng thái
        if (status == 'Done')
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Về Truyện của tôi'),
          ),
        if (status == 'Failed')
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Thử lại'),
          ),
        if (status == 'Pending' || status == 'Running')
          TextButton(onPressed: _reset, child: const Text('Nhập truyện khác')),
      ],
    );
  }
}
