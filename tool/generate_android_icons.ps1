# Sinh icon launcher + splash logo Android từ ảnh nguồn PNG vuông
# (mặc định: assets/icon/vietread_icon_1024.png). Chạy:
#   powershell -ExecutionPolicy Bypass -File tool/generate_android_icons.ps1
#
# CÁC ĐẦU RA (tự ghi vào android/app/src/main/res):
#   mipmap-*dpi/ic_launcher.png            — icon PNG cũ, dùng cho Android < 8.0
#   mipmap-*dpi/ic_launcher_foreground.png — lớp TRƯỚC adaptive icon (Android 8.0+),
#                                            tràn viền 108dp; launcher tự bo mask
#   mipmap-*dpi/ic_launcher_monochrome.png — bản 1 màu (white silhouette) cho
#                                            themed icon Android 13+
#   mipmap-anydpi-v26/ic_launcher.xml      — khai báo adaptive icon (nền xanh ngọc)
#   drawable-*dpi/splash_logo.png           — logo bo góc + đệm trong suốt cho splash
#                                            (Android < 12 đặt giữa launch_background,
#                                             Android 12+ dùng làm animated icon)
#
# Đổi màu nền launcher: sửa <color name="ic_launcher_background"> trong
# android/app/src/main/res/values/colors.xml.
param(
    [string]$Source = (Join-Path $PSScriptRoot "..\assets\icon\vietread_icon_1024.png"),
    [string]$ResDir = (Join-Path $PSScriptRoot "..\android\app\src\main\res")
)

Add-Type -AssemblyName System.Drawing

# Hệ số density: mdpi 1x, hdpi 1.5x, xhdpi 2x, xxhdpi 3x, xxxhdpi 4x
$densities = [ordered]@{
    "mipmap-mdpi"    = 1.0
    "mipmap-hdpi"    = 1.5
    "mipmap-xhdpi"   = 2.0
    "mipmap-xxhdpi"  = 3.0
    "mipmap-xxxhdpi" = 4.0
}

$srcPath = (Resolve-Path $Source).Path
$src = [System.Drawing.Image]::FromFile($srcPath)

function New-Blank([int]$w, [int]$h) {
    $bmp = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    return @($bmp, $g)
}

function Save-Png($bmp, [string]$outPath) {
    $dir = Split-Path $outPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("  {0}  {1}x{1}" -f (Join-Path (Split-Path $dir -Leaf) (Split-Path $outPath -Leaf)), $bmp.Width)
}

# Tỷ lệ luminance ITU-R BT.601 — logo (sách kem, chữ V cam) sáng, nền teal tối.
function Get-Luminance([int]$r, [int]$g, [int]$b) {
    return (0.2126 * $r + 0.7152 * $g + 0.0722 * $b) / 255.0
}

try {
    foreach ($dir in $densities.Keys) {
        $scale = $densities[$dir]
        Write-Output ("{0}:" -f $dir)

        # ---- 1) Icon PNG cũ (Android < 8.0) — tràn viền như trước ----
        $size = [int][Math]::Round(48 * $scale)
        $pair = New-Blank $size $size
        $bmp = $pair[0]; $g = $pair[1]
        $g.DrawImage($src, 0, 0, $size, $size)
        Save-Png $bmp (Join-Path (Join-Path $ResDir $dir) "ic_launcher.png")
        $g.Dispose(); $bmp.Dispose()

        # ---- 2) Lớp trước adaptive icon — canvas 108dp tràn viền ----
        # Logo bright chiếm ~61% giữa ảnh → nằm gọn trong vùng an toàn 66% của mask.
        $fgSize = [int][Math]::Round(108 * $scale)
        $pair = New-Blank $fgSize $fgSize
        $bmp = $pair[0]; $g = $pair[1]
        $g.DrawImage($src, 0, 0, $fgSize, $fgSize)
        Save-Png $bmp (Join-Path (Join-Path $ResDir $dir) "ic_launcher_foreground.png")
        $g.Dispose(); $bmp.Dispose()

        # ---- 3) Monochrome cho themed icon (Android 13+) ----
        # Giữ pixel có luminance > 0.45 (sách + chữ V) → nền trắng, nền teal biến mất.
        $monoSize = [int][Math]::Round(108 * $scale)
        $pair = New-Blank $monoSize $monoSize
        $bmp = $pair[0]; $g = $pair[1]
        $g.DrawImage($src, 0, 0, $monoSize, $monoSize)
        $rect = [System.Drawing.Rectangle]::new(0, 0, $monoSize, $monoSize)
        $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, $bmp.PixelFormat)
        $stride = $data.Stride
        $bytes = [byte[]]::new($stride * $monoSize)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        for ($y = 0; $y -lt $monoSize; $y++) {
            $row = $y * $stride
            for ($x = 0; $x -lt $monoSize; $x++) {
                $i = $row + $x * 4
                $lum = Get-Luminance $bytes[$i + 2] $bytes[$i + 1] $bytes[$i]
                # Alpha mềm quanh ngưỡng 0.45 để viền không răng cưa
                $a = ($lum - 0.35) / 0.20
                if ($a -le 0) { $a = 0 } elseif ($a -ge 1) { $a = 1 }
                $bytes[$i] = 255     # B
                $bytes[$i + 1] = 255 # G
                $bytes[$i + 2] = 255 # R
                $bytes[$i + 3] = [byte][int](255 * $a)
            }
        }
        [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
        $bmp.UnlockBits($data)
        Save-Png $bmp (Join-Path (Join-Path $ResDir $dir) "ic_launcher_monochrome.png")
        $g.Dispose(); $bmp.Dispose()

        # ---- 4) Splash logo: bo góc ~20% + đệm trong suốt 15% ----
        # Frame 120dp: Android < 12 hiện đúng cỡ này giữa màn hình;
        # Android 12+ hệ thống phóng to frame lên 288dp nên tỉ lệ giữ nguyên.
        $frame = [int][Math]::Round(120 * $scale)
        $pair = New-Blank $frame $frame
        $bmp = $pair[0]; $g = $pair[1]
        $pad = [int][Math]::Round($frame * 0.15)
        $content = $frame - 2 * $pad
        $radius = [int][Math]::Round($content * 0.20)
        $clipPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $clipPath.AddArc($pad, $pad, 2 * $radius, 2 * $radius, 180, 90)
        $clipPath.AddArc($frame - $pad - 2 * $radius, $pad, 2 * $radius, 2 * $radius, 270, 90)
        $clipPath.AddArc($frame - $pad - 2 * $radius, $frame - $pad - 2 * $radius, 2 * $radius, 2 * $radius, 0, 90)
        $clipPath.AddArc($pad, $frame - $pad - 2 * $radius, 2 * $radius, 2 * $radius, 90, 90)
        $clipPath.CloseFigure()
        $g.SetClip($clipPath)
        $g.DrawImage($src, $pad, $pad, $content, $content)
        $splashDir = $dir -replace "^mipmap-", "drawable-"
        Save-Png $bmp (Join-Path (Join-Path $ResDir $splashDir) "splash_logo.png")
        $g.Dispose(); $bmp.Dispose()
    }

    # ---- 5) Khai báo adaptive icon: nền xanh ngọc + lớp trước + monochrome ----
    $anydpi = Join-Path $ResDir "mipmap-anydpi-v26"
    if (-not (Test-Path $anydpi)) { New-Item -ItemType Directory -Path $anydpi | Out-Null }
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Tự sinh bởi tool/generate_android_icons.ps1 — đừng sửa tay. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"@
    [System.IO.File]::WriteAllText((Join-Path $anydpi "ic_launcher.xml"), $xml)
    Write-Output "  mipmap-anydpi-v26/ic_launcher.xml (adaptive + monochrome)"
    Write-Output "OK — nhớ UNINSTALL app cũ rồi chạy lại để thấy icon/splash mới."
}
finally {
    $src.Dispose()
}
