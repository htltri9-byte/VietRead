/* ==========================================================================
   VietRead — Migration: Ý nghĩa theo truyện (bộ lọc marker + phản hồi người dùng)

   Thêm 2 bảng (bỏ qua nếu đã tồn tại — chạy lại bao nhiêu lần cũng không lỗi):
     StoryWordChoices   — "Luôn dùng nghĩa này cho truyện này":
                          khóa Trung → nghĩa đã chọn; dịch/dịch lại chương của
                          truyện đó tự dùng nghĩa này, không tạo marker.
     StoryIgnoredWords  — "Không hỏi lại từ này" của RIÊNG bộ truyện
                          (khác file chung no_mark.txt).

   Dữ liệu cũ giữ nguyên (2 bảng này trống khi tạo mới).

   Cách chạy (SSMS): mở file này rồi nhấn F5.
   Cách chạy (thiết bị):
     sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_story_words.sql
   ========================================================================== */

USE VietRead;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.StoryWordChoices', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.StoryWordChoices (
        Id         INT IDENTITY(1,1) NOT NULL,
        StoryId    INT           NOT NULL,
        SourceKey  NVARCHAR(200) NOT NULL,
        ChosenText NVARCHAR(200) NOT NULL,
        CreatedAt  DATETIME2     NOT NULL CONSTRAINT DF_StoryWordChoices_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_StoryWordChoices PRIMARY KEY (Id),
        CONSTRAINT FK_StoryWordChoices_StoryId FOREIGN KEY (StoryId)
            REFERENCES dbo.Stories(Id) ON DELETE CASCADE,
        CONSTRAINT UQ_StoryWordChoices_StoryId_SourceKey UNIQUE (StoryId, SourceKey)
    );
    PRINT N'Đã tạo bảng dbo.StoryWordChoices';
END
GO

IF OBJECT_ID(N'dbo.StoryIgnoredWords', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.StoryIgnoredWords (
        Id        INT IDENTITY(1,1) NOT NULL,
        StoryId   INT           NOT NULL,
        SourceKey NVARCHAR(200) NOT NULL,
        CreatedAt DATETIME2     NOT NULL CONSTRAINT DF_StoryIgnoredWords_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_StoryIgnoredWords PRIMARY KEY (Id),
        CONSTRAINT FK_StoryIgnoredWords_StoryId FOREIGN KEY (StoryId)
            REFERENCES dbo.Stories(Id) ON DELETE CASCADE,
        CONSTRAINT UQ_StoryIgnoredWords_StoryId_SourceKey UNIQUE (StoryId, SourceKey)
    );
    PRINT N'Đã tạo bảng dbo.StoryIgnoredWords';
END
GO

PRINT N'Migration nghĩa theo truyện hoàn tất (chạy lại an toàn).';
GO
