/* ==========================================================================
   VietRead — Migration: Từ điển cá nhân (idempotent)

   Thêm bảng `DictionaryWords` (bỏ qua nếu đã tồn tại — chạy lại không lỗi):
     DictionaryWords — mỗi từ người dùng thêm qua POST /dictionary/names
                       (Zh → Vi + tags), dùng để liệt kê/xoá trong app.
   Từ điển dịch thật vẫn nằm trong `dictionaries/names.txt` (vietphrase.py
   nạp vào bộ nhớ) — bảng này chỉ là sổ theo dõi của từng người dùng.

   Cách chạy (SSMS): mở file này rồi nhấn F5.
   Cách chạy (thiết bị):
     sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_dictionary_words.sql
   ========================================================================== */

USE VietRead;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.DictionaryWords', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DictionaryWords (
        Id        INT IDENTITY(1,1) NOT NULL,
        UserId    INT           NOT NULL,
        Zh        NVARCHAR(100) NOT NULL,
        Vi        NVARCHAR(200) NOT NULL,
        -- Tags tuỳ chọn ("tên riêng, sư huynh") — phân cách bằng dấu phẩy
        Tags      NVARCHAR(200) NULL,
        CreatedAt DATETIME2     NOT NULL CONSTRAINT DF_DictionaryWords_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_DictionaryWords PRIMARY KEY (Id),
        CONSTRAINT FK_DictionaryWords_UserId FOREIGN KEY (UserId)
            REFERENCES dbo.Users(Id) ON DELETE CASCADE,
        -- Một tài khoản không thêm cùng một từ 2 lần
        CONSTRAINT UQ_DictionaryWords_UserId_Zh UNIQUE (UserId, Zh)
    );
    PRINT N'Đã tạo bảng dbo.DictionaryWords';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_DictionaryWords_UserId'
      AND object_id = OBJECT_ID(N'dbo.DictionaryWords')
)
BEGIN
    CREATE INDEX IX_DictionaryWords_UserId ON dbo.DictionaryWords (UserId);
    PRINT N'Đã tạo index IX_DictionaryWords_UserId';
END
GO

PRINT N'Migration từ điển cá nhân hoàn tất (chạy lại an toàn).';
GO
