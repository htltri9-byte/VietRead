/* ==========================================================================
   VietRead — Migration: tách Tác giả (nguyên tác) / Người đăng (idempotent)

   Thêm cột (bỏ qua nếu đã tồn tại — chạy lại bao nhiêu lần cũng không lỗi):
     Stories.OriginalAuthor     NVARCHAR(200) NULL   -- tên tác giả hiển thị (đã Hán-Việt, viết hoa)
     Stories.OriginalAuthorRaw  NVARCHAR(200) NULL   -- tên gốc chữ Trung (nếu có từ nguồn)

   Quan hệ:
     Stories.AuthorId  = NGƯỜI ĐĂNG (tài khoản VietRead đăng/nhập truyện) — GIỮ NGUYÊN.
     Stories.OriginalAuthor = TÁC GIẢ (nguyên tác); NULL nếu không rõ / truyện tự đăng
     nhưng tác giả không ghi.

   Dữ liệu cũ giữ nguyên: mọi hàng hiện có đều NULL ở 2 cột mới (KHÔNG tự suy ra
   từ người đăng — chờ người dùng sửa trong form Sửa truyện).

   Cách chạy (SSMS): mở file này rồi nhấn F5.
   Cách chạy (thiết bị):
     sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_original_author.sql
   ========================================================================== */

USE VietRead;
GO

IF COL_LENGTH(N'dbo.Stories', N'OriginalAuthor') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD OriginalAuthor NVARCHAR(200) NULL;
    PRINT N'Đã thêm dbo.Stories.OriginalAuthor';
END
GO

IF COL_LENGTH(N'dbo.Stories', N'OriginalAuthorRaw') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD OriginalAuthorRaw NVARCHAR(200) NULL;
    PRINT N'Đã thêm dbo.Stories.OriginalAuthorRaw';
END
GO

-- Báo lại số truyện chưa có tác giả (để biết còn bao nhiêu chờ người dùng bổ sung)
DECLARE @missing INT = (SELECT COUNT(*) FROM dbo.Stories WHERE OriginalAuthor IS NULL);
PRINT N'Số truyện còn thiếu OriginalAuthor (NULL): ' + CAST(@missing AS NVARCHAR(20));
GO
