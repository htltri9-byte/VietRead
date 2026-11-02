/* ==========================================================================
   VietRead — Migration: kiểm duyệt truyện trước khi công khai (idempotent)

   Thêm (bỏ qua nếu đã tồn tại — chạy lại bao nhiêu lần cũng không lỗi):
     Users.Role            NVARCHAR(20)  NOT NULL DEFAULT 'user'  (user | admin)
     Stories.ModerationStatus NVARCHAR(20)  NOT NULL DEFAULT 'draft'
         — draft | pending | approved | rejected
     Stories.RejectReason  NVARCHAR(1000) NULL
     Stories.SubmittedAt   DATETIME2      NULL
     Stories.ReviewedAt    DATETIME2      NULL
     Stories.ReviewedBy    INT            NULL  (FK → Users.Id)
     Stories.NeedsRecheck  BIT            NOT NULL DEFAULT 0
     Stories.ScanStatus    NVARCHAR(20)   NULL  (none | clean | flagged | error)
         — CHỈ tạo cột, chưa có logic quét (dành cho dịch vụ quét sau này)
     Stories.ScanSummary   NVARCHAR(MAX)  NULL  (JSON kết quả quét)
     Bảng dbo.ModerationLog(Id, StoryId, AdminId, Action, Reason, CreatedAt)

   Đồng bộ dữ liệu cũ (chạy lại an toàn):
     IsDraft = 1 → ModerationStatus = 'draft'
     IsDraft = 0 → ModerationStatus = 'approved'  (truyện đang hiện không mất)
     IsDraft   := (ModerationStatus <> 'approved')  — hai cột luôn nhất quán:
     IsDraft = 0 CHỈ khi approved; mọi trạng thái còn lại IsDraft = 1 nên
     các câu lệnh cũ lọc "IsDraft = 0" tự động chỉ thấy truyện đã duyệt.

   Cách chạy (SSMS): mở file này rồi nhấn F5.
   Cách chạy (thiết bị):
     sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_moderation.sql
   ========================================================================== */

USE VietRead;
GO

/* ------------------------------ Users.Role ------------------------------ */
IF COL_LENGTH(N'dbo.Users', N'Role') IS NULL
BEGIN
    ALTER TABLE dbo.Users
        ADD Role NVARCHAR(20) NOT NULL CONSTRAINT DF_Users_Role DEFAULT (N'user');
    PRINT N'Đã thêm dbo.Users.Role';
END
GO

/* --------------------------- Stories: kiểm duyệt ------------------------ */
IF COL_LENGTH(N'dbo.Stories', N'ModerationStatus') IS NULL
BEGIN
    ALTER TABLE dbo.Stories
        ADD ModerationStatus NVARCHAR(20) NOT NULL
                CONSTRAINT DF_Stories_ModerationStatus DEFAULT (N'draft');
    PRINT N'Đã thêm dbo.Stories.ModerationStatus';
END
GO

IF COL_LENGTH(N'dbo.Stories', N'RejectReason') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD RejectReason NVARCHAR(1000) NULL;
    PRINT N'Đã thêm dbo.Stories.RejectReason';
END
GO

IF COL_LENGTH(N'dbo.Stories', N'SubmittedAt') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD SubmittedAt DATETIME2 NULL;
    PRINT N'Đã thêm dbo.Stories.SubmittedAt';
END
GO

IF COL_LENGTH(N'dbo.Stories', N'ReviewedAt') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD ReviewedAt DATETIME2 NULL;
    PRINT N'Đã thêm dbo.Stories.ReviewedAt';
END
GO

IF COL_LENGTH(N'dbo.Stories', N'ReviewedBy') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD ReviewedBy INT NULL;
    PRINT N'Đã thêm dbo.Stories.ReviewedBy';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_Stories_ReviewedBy'
      AND parent_object_id = OBJECT_ID(N'dbo.Stories')
)
BEGIN
    ALTER TABLE dbo.Stories WITH CHECK
        ADD CONSTRAINT FK_Stories_ReviewedBy
        FOREIGN KEY (ReviewedBy) REFERENCES dbo.Users(Id);
    PRINT N'Đã tạo FK_Stories_ReviewedBy';
END
GO

IF COL_LENGTH(N'dbo.Stories', N'NeedsRecheck') IS NULL
BEGIN
    ALTER TABLE dbo.Stories
        ADD NeedsRecheck BIT NOT NULL CONSTRAINT DF_Stories_NeedsRecheck DEFAULT (0);
    PRINT N'Đã thêm dbo.Stories.NeedsRecheck';
END
GO

-- Chỗ dành cho dịch vụ quét nội dung TỰ ĐỘNG sau này — giai đoạn này chỉ tạo cột
IF COL_LENGTH(N'dbo.Stories', N'ScanStatus') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD ScanStatus NVARCHAR(20) NULL;
    PRINT N'Đã thêm dbo.Stories.ScanStatus (chưa có logic quét)';
END
GO

IF COL_LENGTH(N'dbo.Stories', N'ScanSummary') IS NULL
BEGIN
    ALTER TABLE dbo.Stories ADD ScanSummary NVARCHAR(MAX) NULL;
    PRINT N'Đã thêm dbo.Stories.ScanSummary (chưa có logic quét)';
END
GO

/* ----------------------------- ModerationLog ---------------------------- */
IF OBJECT_ID(N'dbo.ModerationLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ModerationLog (
        Id        INT IDENTITY(1,1) NOT NULL,
        StoryId   INT           NOT NULL,
        AdminId   INT           NOT NULL,
        Action    NVARCHAR(20)  NOT NULL,          -- approve | reject | unpublish
        Reason    NVARCHAR(1000) NULL,
        CreatedAt DATETIME2     NOT NULL CONSTRAINT DF_ModerationLog_CreatedAt
                        DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_ModerationLog PRIMARY KEY (Id),
        CONSTRAINT FK_ModerationLog_StoryId FOREIGN KEY (StoryId)
            REFERENCES dbo.Stories(Id) ON DELETE CASCADE,
        CONSTRAINT FK_ModerationLog_AdminId FOREIGN KEY (AdminId)
            REFERENCES dbo.Users(Id)
    );
    CREATE INDEX IX_ModerationLog_StoryId ON dbo.ModerationLog (StoryId);
    PRINT N'Đã tạo dbo.ModerationLog';
END
GO

/* --------------------- Chuyển dữ liệu cũ (idempotent) ------------------- */
-- Truyện đã đăng công khai cũ (IsDraft = 0) → approved để không làm mất truyện đang hiện.
-- Chạy lại sau này vẫn an toàn: mọi trạng thái không phải approved đều có IsDraft = 1
-- nên không bị với về approved.
UPDATE dbo.Stories
SET ModerationStatus = N'approved',
    ReviewedAt = COALESCE(ReviewedAt, UpdatedAt)   -- mốc duyệt dữ liệu cũ
WHERE IsDraft = 0
  AND ModerationStatus <> N'approved';
PRINT N'Đã chuyển truyện IsDraft=0 → approved';

-- Truyện nháp cũ (IsDraft = 1): cột ModerationStatus mới thêm đã DEFAULT N'draft'
-- cho mọi hàng cũ nên không cần UPDATE (hàng pending/rejected sau này do code
-- chuyển sẽ có SubmittedAt/ReviewedAt, không đụng tới ở đây).
-- Sửa ngược cho nhất quán: IsDraft = 0 chỉ khi approved (dữ liệu hỏng/nhập tay)
UPDATE dbo.Stories
SET IsDraft = CASE WHEN ModerationStatus = N'approved' THEN 0 ELSE 1 END
WHERE IsDraft <> CASE WHEN ModerationStatus = N'approved' THEN 0 ELSE 1 END;
PRINT N'Đã đồng bộ IsDraft với ModerationStatus';
GO

/* ------------------------------- Index ---------------------------------- */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Stories_ModerationStatus'
      AND object_id = OBJECT_ID(N'dbo.Stories')
)
BEGIN
    CREATE INDEX IX_Stories_ModerationStatus
        ON dbo.Stories (ModerationStatus, SubmittedAt);
    PRINT N'Đã tạo index IX_Stories_ModerationStatus';
END
GO

PRINT N'Migration kiểm duyệt hoàn tất (chạy lại an toàn).';
GO
