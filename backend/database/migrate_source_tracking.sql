/* ==========================================================================
   VietRead — Migration: theo dõi nguồn của truyện/chương (idempotent)

   Thêm cột (bỏ qua nếu đã tồn tại — chạy lại bao nhiêu lần cũng không lỗi):
     Stories.SourceBookId      NVARCHAR(100)  NULL
     Chapters.SourceChapterId  NVARCHAR(200)  NULL
     Chapters.SourceChapterUrl NVARCHAR(1000) NULL
   + unique index lọc (StoryId, SourceChapterId) WHERE SourceChapterId IS NOT NULL
   để chống trùng chương khi thêm chương từ link Qidian.

   Dữ liệu cũ giữ nguyên: mọi hàng hiện có đều NULL ở cột mới.

   Cách chạy (SSMS): mở file này rồi nhấn F5.
   Cách chạy (thiết bị):
     sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_source_tracking.sql
   ========================================================================== */

USE VietRead;
GO

-- Unique index lọc yêu cầu QUOTED_IDENTIFIER ON (sqlcmd có thể đang OFF)
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'dbo.Stories', N'SourceBookId') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD SourceBookId NVARCHAR(100) NULL;
    PRINT N'Đã thêm dbo.Stories.SourceBookId';
END
GO

IF COL_LENGTH(N'dbo.Chapters', N'SourceChapterId') IS NULL
BEGIN
    ALTER TABLE dbo.Chapters ADD SourceChapterId NVARCHAR(200) NULL;
    PRINT N'Đã thêm dbo.Chapters.SourceChapterId';
END
GO

IF COL_LENGTH(N'dbo.Chapters', N'SourceChapterUrl') IS NULL
BEGIN
    ALTER TABLE dbo.Chapters ADD SourceChapterUrl NVARCHAR(1000) NULL;
    PRINT N'Đã thêm dbo.Chapters.SourceChapterUrl';
END
GO

-- Unique index lọc: chống cùng một chương Qidian bị nhập 2 lần vào cùng truyện
-- (chỉ áp dụng hàng có SourceChapterId — hàng cũ NULL vẫn qua được).
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UX_Chapters_StoryId_SourceChapterId'
      AND object_id = OBJECT_ID(N'dbo.Chapters')
)
BEGIN
    CREATE UNIQUE INDEX UX_Chapters_StoryId_SourceChapterId
        ON dbo.Chapters (StoryId, SourceChapterId)
        WHERE SourceChapterId IS NOT NULL;
    PRINT N'Đã tạo unique index UX_Chapters_StoryId_SourceChapterId';
END
GO

PRINT N'Migration theo dõi nguồn hoàn tất (chạy lại an toàn).';
GO
