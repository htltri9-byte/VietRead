/* ==========================================================================
   VietRead — Migration: Tìm & thay thế theo truyện + lịch sử hoàn tác (idempotent)

   Thêm 2 bảng (bỏ qua nếu đã tồn tại — chạy lại bao nhiêu lần cũng không lỗi):
     StoryGlossary    — quy tắc "Tìm & thay thế" riêng của từng truyện,
                        ApplyToFuture=1 → áp dụng cho chương thêm sau này;
     ChapterRevisions — snapshot chương TRƯỚC một lần thay thế (batch gần nhất
                        của mỗi truyện) để hoàn tác.

   Dữ liệu cũ giữ nguyên (2 bảng này trống khi tạo mới).

   Cách chạy (SSMS): mở file này rồi nhấn F5.
   Cách chạy (thiết bị):
     sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_glossary_revisions.sql
   ========================================================================== */

USE VietRead;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.StoryGlossary', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.StoryGlossary (
        Id            INT IDENTITY(1,1) NOT NULL,
        StoryId       INT           NOT NULL,
        FindText      NVARCHAR(200) NOT NULL,
        ReplaceText   NVARCHAR(200) NOT NULL,
        MatchCase     BIT           NOT NULL CONSTRAINT DF_StoryGlossary_MatchCase DEFAULT (0),
        WholeWord     BIT           NOT NULL CONSTRAINT DF_StoryGlossary_WholeWord DEFAULT (0),
        ApplyToFuture BIT           NOT NULL CONSTRAINT DF_StoryGlossary_ApplyToFuture DEFAULT (1),
        CreatedAt     DATETIME2     NOT NULL CONSTRAINT DF_StoryGlossary_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_StoryGlossary PRIMARY KEY (Id),
        CONSTRAINT FK_StoryGlossary_StoryId FOREIGN KEY (StoryId)
            REFERENCES dbo.Stories(Id) ON DELETE CASCADE
    );
    PRINT N'Đã tạo bảng dbo.StoryGlossary';
END
GO

IF OBJECT_ID(N'dbo.ChapterRevisions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ChapterRevisions (
        Id        INT IDENTITY(1,1) NOT NULL,
        ChapterId INT           NOT NULL,
        StoryId   INT           NOT NULL,
        Title     NVARCHAR(255) NOT NULL,
        Content   NVARCHAR(MAX) NOT NULL,
        BatchId   NVARCHAR(36)  NOT NULL,
        CreatedAt DATETIME2     NOT NULL CONSTRAINT DF_ChapterRevisions_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_ChapterRevisions PRIMARY KEY (Id),
        -- StoryId cascade (xoá truyện → mất revision); ChapterId cố tình KHÔNG
        -- cascade như Comments để không tạo 2 đường cascade từ Stories — xoá
        -- chương thì xoá revision trong code (routers/chapters.py).
        CONSTRAINT FK_ChapterRevisions_StoryId FOREIGN KEY (StoryId)
            REFERENCES dbo.Stories(Id) ON DELETE CASCADE,
        CONSTRAINT FK_ChapterRevisions_ChapterId FOREIGN KEY (ChapterId)
            REFERENCES dbo.Chapters(Id)
    );
    PRINT N'Đã tạo bảng dbo.ChapterRevisions';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_StoryGlossary_StoryId'
      AND object_id = OBJECT_ID(N'dbo.StoryGlossary')
)
BEGIN
    CREATE INDEX IX_StoryGlossary_StoryId ON dbo.StoryGlossary (StoryId);
    PRINT N'Đã tạo index IX_StoryGlossary_StoryId';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_ChapterRevisions_StoryId'
      AND object_id = OBJECT_ID(N'dbo.ChapterRevisions')
)
BEGIN
    CREATE INDEX IX_ChapterRevisions_StoryId ON dbo.ChapterRevisions (StoryId);
    PRINT N'Đã tạo index IX_ChapterRevisions_StoryId';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_ChapterRevisions_ChapterId'
      AND object_id = OBJECT_ID(N'dbo.ChapterRevisions')
)
BEGIN
    CREATE INDEX IX_ChapterRevisions_ChapterId ON dbo.ChapterRevisions (ChapterId);
    PRINT N'Đã tạo index IX_ChapterRevisions_ChapterId';
END
GO

PRINT N'Migration Tìm & thay thế hoàn tất (chạy lại an toàn).';
GO
