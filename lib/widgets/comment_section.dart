import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_label.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'skeleton.dart';

/// Tab **Bình luận** của màn chi tiết truyện: ô nhập (chỉ khi đã đăng nhập,
/// ngược lại là lời mời đăng nhập) + danh sách trạng thái / bình luận (A3.6).
///
/// Toàn bộ trạng thái (danh sách, đang gửi, lỗi) do màn chi tiết quản lý —
/// widget này chỉ dựng giao diện từ dữ liệu nhận được.
class CommentSection extends StatelessWidget {
  const CommentSection({
    super.key,
    required this.controller,
    required this.comments,
    required this.loading,
    required this.error,
    required this.sending,
    required this.onSend,
    required this.onDelete,
    required this.onLogin,
    required this.onRetry,
  });

  /// Ô nhập bình luận — controller thuộc màn chi tiết (giữ focus/undo).
  final TextEditingController controller;

  final List<Comment> comments;
  final bool loading;
  final Object? error;
  final bool sending;

  final VoidCallback onSend;

  /// Hỏi xác nhận rồi xoá bình luận — màn chi tiết lo phần xác nhận.
  final ValueChanged<Comment> onDelete;

  final VoidCallback onLogin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // ---------------- Ô nhập / lời mời đăng nhập ----------------
    // AnimatedBuilder để ô nhập hiện ra ngay khi đăng nhập xong.
    final Widget inputBox = AnimatedBuilder(
      animation: AuthService.instance,
      builder: (BuildContext context, _) {
        if (!AuthService.instance.isLoggedIn) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: Text(
                'Đăng nhập để bình luận',
                style: theme.textTheme.titleSmall,
              ),
              subtitle: const Text('Chia sẻ cảm nhận của bạn về truyện.'),
              trailing: FilledButton(
                onPressed: onLogin,
                child: const Text('Đăng nhập'),
              ),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Viết bình luận...',
                      counterText: '',
                      border: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                sending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : IconButton.filled(
                        onPressed: onSend,
                        icon: const Icon(Icons.send_rounded, size: 20),
                        tooltip: 'Gửi bình luận',
                      ),
              ],
            ),
          ),
        );
      },
    );

    const Widget gap = SizedBox(height: 12);

    // ---------------- Trạng thái đang tải ----------------
    if (loading && comments.isEmpty && error == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          inputBox,
          gap,
          const SkeletonBox(width: double.infinity, height: 72, radius: 12),
          const SizedBox(height: 8),
          const SkeletonBox(width: double.infinity, height: 72, radius: 12),
        ],
      );
    }

    // ---------------- Trạng thái lỗi ----------------
    if (error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          inputBox,
          gap,
          ErrorState(
            message: error is ApiException
                ? (error as ApiException).message
                : 'Không tải được bình luận.',
            onRetry: onRetry,
          ),
        ],
      );
    }

    // ---------------- Rỗng ----------------
    if (comments.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          inputBox,
          gap,
          const EmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Chưa có bình luận nào',
            message: 'Hãy là người đầu tiên chia sẻ cảm nhận về truyện này.',
          ),
        ],
      );
    }

    // ---------------- Danh sách ----------------
    final int? myId = AuthService.instance.user?.id;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        inputBox,
        gap,
        Text(
          '${comments.length} bình luận',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final Comment comment in comments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar chữ ký tự đầu tên (giống fallback ảnh bìa)
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: scheme.primary,
                      child: Text(
                        comment.initial,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  comment.userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                formatDateLabel(comment.createdAt),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            comment.content,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    // Chỉ hiện nút xoá khi là bình luận của mình (A3.6)
                    if (myId != null && comment.userId == myId)
                      IconButton(
                        onPressed: () => onDelete(comment),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                        ),
                        tooltip: 'Xoá bình luận',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
