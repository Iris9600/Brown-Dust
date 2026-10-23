param([string]$Source = 'assets/branding/app-icon.png')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = if ([IO.Path]::IsPathRooted($Source)) { $Source } else { Join-Path $projectRoot $Source }
$sourceImage = [Drawing.Image]::FromFile($sourcePath)
try {
    if ($sourceImage.Width -ne $sourceImage.Height) { throw 'The master icon must be square.' }
    $targets = @{}
    foreach ($density in @{mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192}.GetEnumerator()) {
        $targets["android/app/src/main/res/mipmap-$($density.Key)/ic_launcher.png"] = $density.Value
    }
    $catalog = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json') | ConvertFrom-Json
    foreach ($item in $catalog.images) {
        if ($item.filename) {
            $logical = [double]::Parse(($item.size -split 'x')[0], [Globalization.CultureInfo]::InvariantCulture)
            $scale = [double]::Parse($item.scale.TrimEnd('x'), [Globalization.CultureInfo]::InvariantCulture)
            $targets["ios/Runner/Assets.xcassets/AppIcon.appiconset/$($item.filename)"] = [int][Math]::Round($logical * $scale)
        }
    }
    foreach ($size in @(192, 512)) {
        $targets["web/icons/Icon-$size.png"] = $size
        $targets["web/icons/Icon-maskable-$size.png"] = $size
    }
    $targets['web/favicon.png'] = 32
    foreach ($target in $targets.GetEnumerator()) {
        $destination = [IO.Path]::GetFullPath((Join-Path $projectRoot $target.Key))
        if (-not $destination.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Icon target is outside the project.'
        }
        $pixels = [int]$target.Value
        $bitmap = New-Object Drawing.Bitmap($pixels, $pixels, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $attributes = New-Object Drawing.Imaging.ImageAttributes
        try {
            $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#11171D'))
            $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $rect = New-Object Drawing.Rectangle(0, 0, $pixels, $pixels)
            $graphics.DrawImage($sourceImage, $rect, 0, 0, $sourceImage.Width, $sourceImage.Height, [Drawing.GraphicsUnit]::Pixel, $attributes)
            $bitmap.Save($destination, [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $attributes.Dispose()
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
    Write-Output "Updated $($targets.Count) Android, iOS, and web icons."
} finally {
    $sourceImage.Dispose()
}