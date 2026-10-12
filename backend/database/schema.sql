/* ==========================================================================
   VietRead — CSDL SQL Server (Phần C2 của đề bài)
   Nguồn chuẩn cấu trúc bảng; backend/app/models.py chỉ mô tả lại để đọc/ghi.

   Cách chạy (SSMS): mở file này rồi nhấn F5.
   Cách chạy (thiết bị): sqlcmd -S localhost -E -C -b -f 65001 -i schema.sql

   Chạy lại khi bảng đã tồn tại sẽ báo lỗi "already exists" — đó là bình thường.
   Nếu muốn làm lại từ đầu, chạy câu lệnh reset trước:
       ALTER DATABASE VietRead SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
       DROP DATABASE VietRead;
   ========================================================================== */

IF DB_ID(N'VietRead') IS NULL
BEGIN
    CREATE DATABASE VietRead;
END
GO

USE VietRead;
GO

-- Unique index lọc (dưới đây) yêu cầu QUOTED_IDENTIFIER ON
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------ Users ------------------------------ */
CREATE TABLE dbo.Users (
    Id           INT IDENTITY(1,1) NOT NULL,
    Name         NVARCHAR(100)  NOT NULL,
    Email        NVARCHAR(255)  NOT NULL,
    PasswordHash NVARCHAR(255)  NOT NULL,
    AvatarUrl    NVARCHAR(500)  NULL,
    CreatedAt    DATETIME2      NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Users PRIMARY KEY (Id),
    CONSTRAINT UQ_Users_Email UNIQUE (Email)
);
GO

/* ------------------------------ Genres ----------------------------- */
CREATE TABLE dbo.Genres (
    Id   INT IDENTITY(1,1) NOT NULL,
    Name NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Genres PRIMARY KEY (Id),
    CONSTRAINT UQ_Genres_Name UNIQUE (Name)
);
GO

/* ------------------------------ Stories ---------------------------- */
CREATE TABLE dbo.Stories (
    Id          INT IDENTITY(1,1) NOT NULL,
    AuthorId    INT            NOT NULL,
    Title       NVARCHAR(255)  NOT NULL,
    Description NVARCHAR(MAX)  NULL,
    CoverUrl    NVARCHAR(500)  NULL,
    Status      NVARCHAR(20)   NOT NULL CONSTRAINT DF_Stories_Status DEFAULT (N'ongoing'), -- ongoing | completed
    Rating      DECIMAL(3,2)   NOT NULL CONSTRAINT DF_Stories_Rating DEFAULT (0),
    SourceUrl   NVARCHAR(1000) NULL,
    -- Mã truyện trên nguồn (vd: bookId Qidian) — chống nhầm chương khi thêm link
    SourceBookId NVARCHAR(100) NULL,
    IsDraft     BIT            NOT NULL CONSTRAINT DF_Stories_IsDraft DEFAULT (0),
    CreatedAt   DATETIME2      NOT NULL CONSTRAINT DF_Stories_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt   DATETIME2      NOT NULL CONSTRAINT DF_Stories_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Stories PRIMARY KEY (Id),
    CONSTRAINT FK_Stories_AuthorId FOREIGN KEY (AuthorId) REFERENCES dbo.Users(Id)
);
GO

/* ---------------------------- StoryGenres -------------------------- */
CREATE TABLE dbo.StoryGenres (
    StoryId INT NOT NULL,
    GenreId INT NOT NULL,
    CONSTRAINT PK_StoryGenres PRIMARY KEY (StoryId, GenreId),
    CONSTRAINT FK_StoryGenres_StoryId FOREIGN KEY (StoryId) REFERENCES dbo.Stories(Id) ON DELETE CASCADE,
    CONSTRAINT FK_StoryGenres_GenreId FOREIGN KEY (GenreId) REFERENCES dbo.Genres(Id) ON DELETE CASCADE
);
GO

/* ----------------------------- Chapters ---------------------------- */
CREATE TABLE dbo.Chapters (
    Id              INT IDENTITY(1,1) NOT NULL,
    StoryId         INT            NOT NULL,
    ChapterIndex    INT            NOT NULL,
    Title           NVARCHAR(255)  NOT NULL,
    Content         NVARCHAR(MAX)  NOT NULL,
    OriginalContent NVARCHAR(MAX)  NULL,
    -- Mã chương + link trên nguồn (vd: Qidian) — chống trùng khi thêm chương mới
    SourceChapterId  NVARCHAR(200)  NULL,
    SourceChapterUrl NVARCHAR(1000) NULL,
    CreatedAt       DATETIME2      NOT NULL CONSTRAINT DF_Chapters_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt       DATETIME2      NOT NULL CONSTRAINT DF_Chapters_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Chapters PRIMARY KEY (Id),
    CONSTRAINT UQ_Chapters_StoryId_ChapterIndex UNIQUE (StoryId, ChapterIndex),
    CONSTRAINT FK_Chapters_StoryId FOREIGN KEY (StoryId) REFERENCES dbo.Stories(Id) ON DELETE CASCADE
);
GO

/* ----------------------------- Comments ---------------------------- */
CREATE TABLE dbo.Comments (
    Id        INT IDENTITY(1,1) NOT NULL,
    StoryId   INT            NOT NULL,
    ChapterId INT            NULL,
    UserId    INT            NOT NULL,
    Content   NVARCHAR(MAX)  NOT NULL,
    CreatedAt DATETIME2      NOT NULL CONSTRAINT DF_Comments_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Comments PRIMARY KEY (Id),
    CONSTRAINT FK_Comments_StoryId FOREIGN KEY (StoryId) REFERENCES dbo.Stories(Id) ON DELETE CASCADE,
    -- ChapterId cố tình KHÔNG cascade: Stories -> Chapters -> Comments sẽ tạo
    -- 2 đường cascade (lỗi của SQL Server). Xoá chương phải xoá comment trong code.
    CONSTRAINT FK_Comments_ChapterId FOREIGN KEY (ChapterId) REFERENCES dbo.Chapters(Id),
    CONSTRAINT FK_Comments_UserId FOREIGN KEY (UserId) REFERENCES dbo.Users(Id) ON DELETE CASCADE
);
GO

/* ------------------------------ Follows ---------------------------- */
CREATE TABLE dbo.Follows (
    UserId    INT      NOT NULL,
    StoryId   INT      NOT NULL,
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Follows_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Follows PRIMARY KEY (UserId, StoryId),
    CONSTRAINT FK_Follows_UserId FOREIGN KEY (UserId) REFERENCES dbo.Users(Id) ON DELETE CASCADE,
    CONSTRAINT FK_Follows_StoryId FOREIGN KEY (StoryId) REFERENCES dbo.Stories(Id) ON DELETE CASCADE
);
GO

/* ---------------------------- ImportJobs --------------------------- */
CREATE TABLE dbo.ImportJobs (
    Id         INT IDENTITY(1,1) NOT NULL,
    UserId     INT            NOT NULL,
    SourceUrl  NVARCHAR(1000) NOT NULL,
    TargetLang NVARCHAR(20)   NOT NULL CONSTRAINT DF_ImportJobs_TargetLang DEFAULT (N'vi'),
    Status     NVARCHAR(20)   NOT NULL CONSTRAINT DF_ImportJobs_Status DEFAULT (N'Pending'), -- Pending | Running | Done | Failed
    Progress   INT            NOT NULL CONSTRAINT DF_ImportJobs_Progress DEFAULT (0),
    StoryId    INT            NULL,
    Error      NVARCHAR(MAX)  NULL,
    CreatedAt  DATETIME2      NOT NULL CONSTRAINT DF_ImportJobs_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt  DATETIME2      NOT NULL CONSTRAINT DF_ImportJobs_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ImportJobs PRIMARY KEY (Id),
    CONSTRAINT FK_ImportJobs_UserId FOREIGN KEY (UserId) REFERENCES dbo.Users(Id) ON DELETE CASCADE,
    CONSTRAINT FK_ImportJobs_StoryId FOREIGN KEY (StoryId) REFERENCES dbo.Stories(Id) ON DELETE SET NULL
);
GO

/* ------------------------------ Index ------------------------------ */
-- Danh sách truyện của một tác giả (trang "Truyện của tôi")
CREATE INDEX IX_Stories_AuthorId ON dbo.Stories (AuthorId);
-- Sắp xếp "Mới cập nhật"
CREATE INDEX IX_Stories_UpdatedAt ON dbo.Stories (UpdatedAt DESC);
-- Ô tìm kiếm theo tên (LIKE N'%...%')
CREATE INDEX IX_Stories_Title ON dbo.Stories (Title);
-- Danh sách chương của một truyện
CREATE INDEX IX_Chapters_StoryId ON dbo.Chapters (StoryId);
-- Chặn trùng chương cùng nguồn trong một truyện (bỏ qua hàng SourceChapterId NULL)
CREATE UNIQUE INDEX UX_Chapters_StoryId_SourceChapterId
    ON dbo.Chapters (StoryId, SourceChapterId)
    WHERE SourceChapterId IS NOT NULL;
-- Danh sách bình luận theo truyện
CREATE INDEX IX_Comments_StoryId ON dbo.Comments (StoryId);
CREATE INDEX IX_Comments_UserId ON dbo.Comments (UserId);
-- Truyện được theo dõi nhiều / kiểm tra "tôi có theo dõi không"
CREATE INDEX IX_Follows_StoryId ON dbo.Follows (StoryId);
-- Quan hệ thể loại theo chiều ngược (lấy thể loại của truyện)
CREATE INDEX IX_StoryGenres_GenreId ON dbo.StoryGenres (GenreId);
-- Job import của người dùng
CREATE INDEX IX_ImportJobs_UserId ON dbo.ImportJobs (UserId);
GO

PRINT N'Đã tạo/xây dựng xong CSDL VietRead.';
GO
