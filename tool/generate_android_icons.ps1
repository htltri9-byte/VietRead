# Sinh lại icon launcher Android (mipmap-*) từ ảnh nguồn PNG vuông (mặc định:
# assets/icon/vietread_icon_1024.png). Chạy:
#   powershell -ExecutionPolicy Bypass -File tool/generate_android_icons.ps1
param(
    [string]$Source = (Join-Path $PSScriptRoot "..\assets\icon\vietread_icon_1024.png"),
    [string]$ResDir = (Join-Path $PSScriptRoot "..\android\app\src\main\res")
)

Add-Type -AssemblyName System.Drawing

# Kích thước icon theo density Android (dp * dpi / 160)
$sizes = [ordered]@{
    "mipmap-mdpi"    = 48
    "mipmap-hdpi"    = 72
    "mipmap-xhdpi"   = 96
    "mipmap-xxhdpi"  = 144
    "mipmap-xxxhdpi" = 192
}

$srcPath = (Resolve-Path $Source).Path
$src = [System.Drawing.Image]::FromFile($srcPath)
try {
    foreach ($dir in $sizes.Keys) {
        $size = $sizes[$dir]
        $bmp = New-Object System.Drawing.Bitmap $size, $size
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.DrawImage($src, 0, 0, $size, $size)
            $out = Join-Path (Join-Path $ResDir $dir) "ic_launcher.png"
            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Output ("{0}\ic_launcher.png -> {1}x{1}" -f $dir, $size)
        }
        finally {
            $g.Dispose()
            $bmp.Dispose()
        }
    }
}
finally {
    $src.Dispose()
}
Write-Output "OK"
