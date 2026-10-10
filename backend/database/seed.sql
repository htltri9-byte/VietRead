/* ==========================================================================
   VietRead — Dữ liệu mẫu (chạy sau schema.sql)
   Cách chạy (SSMS): mở file này rồi nhấn F5 (đang chọn DB VietRead).
   Cách chạy (thiết bị):
       sqlcmd -S localhost -E -C -b -f 65001 -i seed.sql

   Script an toàn khi chạy lại: nếu đã có truyện mẫu thì bỏ qua.
   Tài khoản demo (mật khẩu chung: VietRead@123):
       tacgia@vietread.vn   — tác giả, có truyện
       docgia@vietread.vn   — độc giả, có theo dõi + bình luận
   ========================================================================== */

USE VietRead;
GO

IF EXISTS (SELECT 1 FROM dbo.Stories)
BEGIN
    PRINT N'Dữ liệu mẫu đã tồn tại — bỏ qua seed.';
END
ELSE
BEGIN
    SET NOCOUNT ON;

    /* ------------------------- Thể loại ------------------------- */
    INSERT INTO dbo.Genres (Name) VALUES
        (N'Tiên Hiệp'),
        (N'Huyền Huyễn'),
        (N'Kiếm Hiệp'),
        (N'Đô Thị'),
        (N'Ngôn Tình'),
        (N'Xuyên Không'),
        (N'Hệ Thống'),
        (N'Trinh Thám');

    /* ------------------------ Người dùng ------------------------ */
    -- PasswordHash = bcrypt của "VietRead@123" (sinh bằng passlib/bcrypt)
    INSERT INTO dbo.Users (Name, Email, PasswordHash, AvatarUrl) VALUES
        (N'Trần Nhật Nam',  N'tacgia@vietread.vn', N'$2b$12$n7kUwzeVzOoWwqU0XJgjxOrMOKPH59kvMm4d7ssFo1jyNQok2aw9y', NULL),
        (N'Lê Minh Anh',    N'docgia@vietread.vn', N'$2b$12$n7kUwzeVzOoWwqU0XJgjxOrMOKPH59kvMm4d7ssFo1jyNQok2aw9y', NULL);

    DECLARE @authorId INT = (SELECT Id FROM dbo.Users WHERE Email = N'tacgia@vietread.vn');
    DECLARE @readerId INT = (SELECT Id FROM dbo.Users WHERE Email = N'docgia@vietread.vn');

    /* --------------------------- Truyện 1 --------------------------- */
    INSERT INTO dbo.Stories (AuthorId, Title, Description, CoverUrl, Status, Rating, SourceUrl, IsDraft)
    VALUES (
        @authorId,
        N'Kiếm Sư Vọng Tường',
        N'Một thiếu niên đói nghèo ở biên cương vô tình thức tỉnh kiếm ý vạn năm. Để tìm lại sư phụ mất tích, hắn bước lên con đường tu kiếm đầy chông gai, từ tiểu trận đến trấn áp thiên kiêu.'
        , NULL, N'ongoing', 4.50, NULL, 0
    );
    DECLARE @s1 INT = SCOPE_IDENTITY();

    INSERT INTO dbo.Chapters (StoryId, ChapterIndex, Title, Content) VALUES
        (@s1, 1, N'Chương 1: Kiếm Ngưng Tường',
         N'Hồi ấy trời vừa sáng, sương còn đọng trên ngọn cỏ biên thành. Thanh Niên tên Lục Vọng Quang đang kéo xe củi qua cổng chợ thì nghe thấy một tiếng vang rất khẽ, như thể có ai đó gõ vào tấm gương bằng sắt.' + NCHAR(10) +
         N'Hắn dừng bước, bàn tay chai sần vẫn nắm chắc dây thừng. Tiếng vang ấy không đến từ bên ngoài, mà vọng ra từ trong xương cốt hắn.' + NCHAR(10) +
         N'Từ hôm đó, mỗi khi hắn cầm lên thanh kiếm gỗ cũ của sư phụ, lại có một đạo kiếm ý mỏng như sợi tơ bám trên ngón tay. Người trong trấn bảo hắn điên, nhưng chính hắn biết: kiếm ý ấy đang chờ một ngày thức tỉnh.'),
        (@s1, 2, N'Chương 2: Trấn Thiên Tháp',
         N'Trấn Thiên Tháp cao chín tầng, mỗi tầng đặt một thanh kiếm cổ. Đệ tử các phong xếp hàng cả buổi sáng mới đến lượt bước lên tầng thứ nhất.' + NCHAR(10) +
         N'Lục Vọng Quang chỉ có một ngày, vì ngày mai hắn phải theo xe hàng rời khỏi biên thành. Hắn đặt tay lên lan can, kiếm ý trong người tựa như nước lũ tràn về.' + NCHAR(10) +
         N'Không ai ngờ rằng kẻ không có linh căn lại đẩy được cánh cửa tầng hai chỉ bằng một cú chạm.'),
        (@s1, 3, N'Chương 3: Lời Hứa Của Sư Phụ',
         N'Đêm ấy, trong mộng hắn thấy sư phụ ngồi bên đống lửa, thanh kiếm dài gãy đôi đặt ngang đầu gối.' + NCHAR(10) +
         N'- Nếu một ngày ngươi tìm thấy ta, đừng tin vào những gì mắt ngươi thấy. Sư phụ nói, lửa trong mỏng tắt phụt.' + NCHAR(10) +
         N'Hắn tỉnh giấc, trong tay nắm chặt mảnh vải màu tro, trên vải thêu một chữ: Tường.');

    /* --------------------------- Truyện 2 --------------------------- */
    INSERT INTO dbo.Stories (AuthorId, Title, Description, CoverUrl, Status, Rating, SourceUrl, IsDraft)
    VALUES (
        @authorId,
        N'Phố Đèn Neon',
        N'Cậu sinh viên năm cuối đi giao hàng bằng xe đạp giữa thành phố không bao giờ ngủ. Một đêm, cậu gặp cô gái bán hoa ngồi khóc dưới đèn neon xanh — và cuộc đời cậu rẽ sang một hướng khác.'
        , NULL, N'completed', 4.20, NULL, 0
    );
    DECLARE @s2 INT = SCOPE_IDENTITY();

    INSERT INTO dbo.Chapters (StoryId, ChapterIndex, Title, Content) VALUES
        (@s2, 1, N'Chương 1: Mười Hai Giờ Đêm',
         N'Tiếng chuông đồng hồ điểm nửa đêm, xe đạp của Huy rít lên trên mặt đường ướt. Đèn neon của cửa hàng tiện lợi hắt màu xanh lên vai áo khoác của cậu.' + NCHAR(10) +
         N'Cô gái ngồi bên thùng hàng, bó hoa cẩm chướng đã tàn một nửa. Cô không khóc thành tiếng, chỉ nước mắt là không ngừng.' + NCHAR(10) +
         N'Huy dựng xe, đưa cho cô hộp sữa ấm vừa mua. Đó là lần đầu tiên hai người nói chuyện.'),
        (@s2, 2, N'Chương 2: Tiệm Hoa Cuối Hẻm',
         N'Tiệm hoa nhỏ nằm cuối hẻm 47, bảng hiệu chỉ có một chữ: An. Cậu đến đó mỗi tối sau khi xong việc giao hàng.' + NCHAR(10) +
         N'Người ta bảo hẻm này sắp bị giải tỏa, nhưng cô vẫn cắt hoa mỗi sáng như thể thời gian không đi qua nơi này.'),
        (@s2, 3, N'Chương 3: Ánh Đèn Tắt',
         N'Ngày cuối cùng của tiệm hoa, Huy chở cả thùng hoa lên sân thượng nhà kho bỏ hoang. Từ đó nhìn xuống, cả con phố như một dải lụa ánh sáng.' + NCHAR(10) +
         N'- Cậu có tin là đèn neon cũng biết buồn không? Cô hỏi. Huy không trả lời, chỉ nắm chặt tay cô hơn.');

    /* --------------------------- Truyện 3 --------------------------- */
    INSERT INTO dbo.Stories (AuthorId, Title, Description, CoverUrl, Status, Rating, SourceUrl, IsDraft)
    VALUES (
        @authorId,
        N'Hoàng Đạo Chi Tâm',
        N'Sau khi trời đất phân tách, mười hai hoàng đạo rơi xuống nhân gian. Người nắm giữ tâm của một hoàng đạo sẽ phải gánh chịu cả nghiệp lực của chòm sao ấy.'
        , NULL, N'ongoing', 4.80, NULL, 0
    );
    DECLARE @s3 INT = SCOPE_IDENTITY();

    INSERT INTO dbo.Chapters (StoryId, ChapterIndex, Title, Content) VALUES
        (@s3, 1, N'Chương 1: Sao Rơi Vào Lòng Bàn Tay',
         N'Thu ấy, sao rơi nhiều hơn mọi năm. Có người nhặt được mảnh sao, sau đó cả đời không thể ngủ yên.' + NCHAR(10) +
         N'Kỷ Tinh Nhất, con trai của một thợ rèn, nhặt được mảnh sao màu xanh khi nó còn nóng hổi. Cậu không biết rằng đó là tâm của Hoàng Đạo.' + NCHAR(10) +
         N'Từ đêm ấy, mỗi lần cậu hít thở, trên trời lại có một ngôi sao mờ đi một chút.'),
        (@s3, 2, N'Chương 2: Nghiệp Lực',
         N'Sư phụ nói, gánh sao thì phải gánh luôn nghiệp của sao. Kỷ Tinh Nhất chưa hiểu, cho đến ngày cậu gặp cô gái mang theo một vệt sáng màu đỏ trên mắt.' + NCHAR(10) +
         N'- Ngươi cũng lấy được một mảnh à? Cô cười, nụ cười buồn hơn cả đêm trường.'),
        (@s3, 3, N'Chương 3: Trận Đồ Tinh Đẩu',
         N'Để tháo gỡ nghiệp lực, cậu phải tìm đủ mười hai mảnh tâm trước khi sao băng cắt ngang bầu trời.' + NCHAR(10) +
         N'Chặng đường đầu tiên bắt đầu từ ngôi làng không có bóng trăng.');

    /* --------------------------- Truyện 4 --------------------------- */
    INSERT INTO dbo.Stories (AuthorId, Title, Description, CoverUrl, Status, Rating, SourceUrl, IsDraft)
    VALUES (
        @authorId,
        N'Xuyên Không Làm Giàu Ở Tống Triều',
        N'Một đầu bếp quán nhậu xuyên về thời Tống, mang theo công thức nước mắm và quyết tâm mở chuỗi tiệm ăn đầu tiên trong lịch sử.'
        , NULL, N'ongoing', 4.10, NULL, 0
    );
    DECLARE @s4 INT = SCOPE_IDENTITY();

    INSERT INTO dbo.Chapters (StoryId, ChapterIndex, Title, Content) VALUES
        (@s4, 1, N'Chương 1: Bát Mì Đầu Tiên',
         N'Hồi tỉnh lại, hắn đang nằm trong sạp rau ở chợ Đông. Người ta bảo hắn là Lý Tiểu Mậu, con nhà làm mì đã ba đời.' + NCHAR(10) +
         N'Hắn thử nấu lại bát mì theo cách của quán mình ở năm 2025, cả dãy phố im bặt. Ông chủ quán đối diện sang hỏi mua công thức, giá ba quan bạc.'),
        (@s4, 2, N'Chương 2: Bí Quyết Nước Mắm',
         N'Nước mắm kiểu mới làm cả Khai Phúc Phường náo động. Có kẻ muốn hợp tác, cũng có kẻ muốn cướp công thức.' + NCHAR(10) +
         N'Lý Tiểu Mậu đóng cửa tiệm ba ngày, rồi mở ra với biển hiệu mới: Quán Ăn Kết Nối.');

    /* ------------------- Thể loại cho từng truyện -------------------- */
    INSERT INTO dbo.StoryGenres (StoryId, GenreId)
    SELECT @s1, Id FROM dbo.Genres WHERE Name IN (N'Tiên Hiệp', N'Kiếm Hiệp');
    INSERT INTO dbo.StoryGenres (StoryId, GenreId)
    SELECT @s2, Id FROM dbo.Genres WHERE Name IN (N'Đô Thị', N'Ngôn Tình');
    INSERT INTO dbo.StoryGenres (StoryId, GenreId)
    SELECT @s3, Id FROM dbo.Genres WHERE Name IN (N'Huyền Huyễn', N'Trinh Thám');
    INSERT INTO dbo.StoryGenres (StoryId, GenreId)
    SELECT @s4, Id FROM dbo.Genres WHERE Name IN (N'Xuyên Không', N'Hệ Thống');

    /* ------------------- Theo dõi + bình luận mẫu ------------------ */
    INSERT INTO dbo.Follows (UserId, StoryId) VALUES (@readerId, @s1);

    INSERT INTO dbo.Comments (StoryId, ChapterId, UserId, Content)
    VALUES (@s1, NULL, @readerId, N'Truyện đọc cuốn lắm, mong tác giả ra chương nhanh!');

    PRINT N'Đã nạp dữ liệu mẫu cho VietRead.';
END
GO
