import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/floating_nav.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';

/// Lớp phủ chính: 4 tab + thanh điều hướng viên thuốc nổi (Bước 3).
///
/// Mỗi tab giữ nguyên trạng thái nhờ IndexedStack (chuyển qua lại không mất dữ liệu).
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.api});

  /// Tiêm nguồn dữ liệu cho các tab (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  /// Tab shell đang chọn — LibraryScreen nghe để **tải lại dữ liệu mỗi lần
  /// quay về tab Tủ sách** (IndexedStack giữ state cũ nên nếu không chủ động
  /// reload thì theo dõi/lịch sử/đã tải vẫn hiển thị dữ liệu đã lưu từ trước).
  final ValueNotifier<int> _tabNotifier = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tabNotifier.dispose();
    super.dispose();
  }

  static const List<NavItem> _items = [
    // outline khi chưa chọn, filled khi đang chọn (cùng kích thước)
    NavItem(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      label: 'Khám phá',
    ),
    NavItem(
      icon: Icons.library_books_outlined,
      selectedIcon: Icons.library_books,
      label: 'Tủ sách',
    ),
    NavItem(
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note,
      label: 'Đăng truyện',
    ),
    NavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Tài khoản',
    ),
  ];

  /// Các tab — tạo 1 lần để `IndexedStack` giữ nguyên trạng thái mỗi tab.
  late final List<Widget> _screens = <Widget>[
    HomeScreen(api: widget.api),
    LibraryScreen(api: widget.api, shellTab: _tabNotifier),
    UploadScreen(api: widget.api),
    // "Truyện của tôi" ở tab Tài khoản → nhảy sang tab Đăng truyện (Bước 9).
    ProfileScreen(onOpenMyStories: () => _onTap(2), api: widget.api),
  ];

  /// Chuyển tab khi chạm vào mục trong thanh nav.
  void _onTap(int index) {
    setState(() => _currentIndex = index);
    _tabNotifier.value = index; // báo cho Tủ sách biết vừa được chọn lại
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: FloatingNav(
        items: _items,
        currentIndex: _currentIndex,
        onChanged: _onTap,
      ),
    );
  }
}
