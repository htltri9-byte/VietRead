import 'package:flutter/material.dart';

import '../models/story.dart';

/// Tín chỉ truyện — **Tác giả (nguyên tác)** và **Người đăng** — dùng chung
/// ở màn Chi tiết truyện (hai dòng) và các thẻ/thẻ nhỏ (một dòng).
///
/// Hai khái niệm khác nhau:
/// - *Tác giả*: người sáng tác truyện gốc (với truyện nhập thì tác giả trên
///   nguồn gốc, ví dụ Qidian). Rỗng → hiện `Chưa rõ`.
/// - *Người đăng*: tài khoản VietRead đã đăng/nhập truyện lên app.
class StoryCredits extends StatelessWidget {
  const StoryCredits({super.key, required this.story});

  final Story story;

  /// Một dòng cho thẻ nhỏ (chỉ Tác giả, không thêm người đăng để khỏi chật).
  /// Rỗng → `Chưa rõ`.
  static String cardAuthor(Story story) {
    final String clean = (story.originalAuthor ?? '').trim();
    return clean.isEmpty ? 'Chưa rõ' : clean;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String uploader = (story.uploaderName ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _CreditLine(label: 'Tác giả', name: cardAuthor(story), theme: theme),
        if (uploader.isNotEmpty)
          _CreditLine(label: 'Người đăng', name: uploader, theme: theme),
      ],
    );
  }
}

class _CreditLine extends StatelessWidget {
  const _CreditLine({
    required this.label,
    required this.name,
    required this.theme,
  });

  final String label;
  final String name;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: theme.textTheme.bodySmall,
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          TextSpan(
            text: name,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
