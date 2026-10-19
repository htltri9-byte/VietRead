/* ==========================================================================
   VietRead — Migration: Học hành vi người đăng (quy tắc bỏ marker toàn cục)

   Thêm 2 bảng (bỏ qua nếu đã tồn tại — chạy lại bao nhiêu lần cũng không lỗi):
     UserWordStats  — thống kê số lượt "Không hỏi lại từ này" của MỖI người
                      dùng theo khóa (gộp mọi truyện; UNIQUE(UserId, SourceKey)).
     UserMarkRules  — quy tắc sinh ra khi UserWordStats.SkipCount chạm
                      LEARN_SKIP_THRESHOLD (.env, mặc định 5): khoá không
                      tạo marker nữa ở MỌI truyện của người dùng đó.
                      Xoá quy tắc (GET/DELETE /me/mark-rules) → marker trở lại.

   Dữ liệu cũ giữ nguyên (2 bảng này trống khi tạo mới).

   Cách chạy (SSMS): mở file này rồi nhấn F5.
   Cách chạy (thiết bị):
     sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_learn_rules.sql
   ========================================================================== */

USE VietRead;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.UserWordStats', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserWordStats (
        Id        INT IDENTITY(1,1) NOT NULL,
        UserId    INT           NOT NULL,
        SourceKey NVARCHAR(200) NOT NULL,
        SkipCount INT           NOT NULL CONSTRAINT DF_UserWordStats_SkipCount DEFAULT (1),
        UpdatedAt DATETIME2     NOT NULL CONSTRAINT DF_UserWordStats_UpdatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_UserWordStats PRIMARY KEY (Id),
        CONSTRAINT FK_UserWordStats_UserId FOREIGN KEY (UserId)
            REFERENCES dbo.Users(Id) ON DELETE CASCADE,
        CONSTRAINT UQ_UserWordStats_UserId_SourceKey UNIQUE (UserId, SourceKey)
    );
    PRINT N'Đã tạo bảng dbo.UserWordStats';
END
GO

IF OBJECT_ID(N'dbo.UserMarkRules', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserMarkRules (
        Id        INT IDENTITY(1,1) NOT NULL,
        UserId    INT           NOT NULL,
        SourceKey NVARCHAR(200) NOT NULL,
        SkipCount INT           NOT NULL CONSTRAINT DF_UserMarkRules_SkipCount DEFAULT (0),
        CreatedAt DATETIME2     NOT NULL CONSTRAINT DF_UserMarkRules_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_UserMarkRules PRIMARY KEY (Id),
        CONSTRAINT FK_UserMarkRules_UserId FOREIGN KEY (UserId)
            REFERENCES dbo.Users(Id) ON DELETE CASCADE,
        CONSTRAINT UQ_UserMarkRules_UserId_SourceKey UNIQUE (UserId, SourceKey)
    );
    PRINT N'Đã tạo bảng dbo.UserMarkRules';
END
GO

PRINT N'Migration học hành vi hoàn tất (chạy lại an toàn).';
GO