Add-Type -AssemblyName System.Drawing

function New-Font([float]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
  return New-Object System.Drawing.Font("Arial", $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Draw-Text($g, $text, $font, $brush, [float]$x, [float]$y) {
  $g.DrawString($text, $font, $brush, $x, $y)
}

function Draw-CenteredText($g, $text, $font, $brush, [float]$x, [float]$y, [float]$w, [float]$h) {
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $rect = New-Object System.Drawing.RectangleF($x, $y, $w, $h)
  $g.DrawString($text, $font, $brush, $rect, $sf)
}

function Draw-Box($g, $pen, $brush, [float]$x, [float]$y, [float]$w, [float]$h) {
  if ($brush) { $g.FillRectangle($brush, $x, $y, $w, $h) }
  $g.DrawRectangle($pen, $x, $y, $w, $h)
}

function Draw-MetricBox($g, $title, $value, [float]$x, [float]$y, [float]$w, [float]$h) {
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60,60,60), 2)
  $fill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245,247,250))
  $titleFont = New-Font 18 ([System.Drawing.FontStyle]::Bold)
  $valueFont = New-Font 28 ([System.Drawing.FontStyle]::Bold)
  $brush = [System.Drawing.Brushes]::Black
  Draw-Box $g $pen $fill $x $y $w $h
  Draw-CenteredText $g $title $titleFont $brush $x ($y + 10) $w 30
  Draw-CenteredText $g $value $valueFont $brush $x ($y + 38) $w 42
}

function Parse-Float([string]$s) {
  return [double]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)
}

$repo = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $repo "course_report_ieee"
$figDir = Join-Path $reportDir "figures"
$timingPath = Join-Path $reportDir "single_siso_timing_report.txt"
$powerPath = Join-Path $reportDir "single_siso_power_1.txt"

$timing = Get-Content $timingPath -Raw
$power = Get-Content $powerPath -Raw

$timingSummary = [regex]::Match($timing, '^\s*(?<wns>-?\d+\.\d+)\s+(?<tns>-?\d+\.\d+)\s+(?<fail>\d+)\s+(?<total>\d+)\s+(?<whs>-?\d+\.\d+)\s+(?<ths>-?\d+\.\d+)\s+(?<hfail>\d+)\s+(?<htotal>\d+)\s+(?<wpws>-?\d+\.\d+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
$clockSummary = [regex]::Match($timing, '^\s*clk\s+\{[^\}]+\}\s+(?<period>\d+\.\d+)\s+(?<freq>\d+\.\d+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
$pathSummary = [regex]::Match($timing, 'Requirement:\s+(?<req>\d+\.\d+)ns.*?Data Path Delay:\s+(?<delay>\d+\.\d+)ns\s+\(logic\s+(?<logic>\d+\.\d+)ns.*?route\s+(?<route>\d+\.\d+)ns.*?Logic Levels:\s+(?<levels>\d+)', [System.Text.RegularExpressions.RegexOptions]::Singleline)

$wns = Parse-Float $timingSummary.Groups['wns'].Value
$whs = Parse-Float $timingSummary.Groups['whs'].Value
$setupFail = [int]$timingSummary.Groups['fail'].Value
$setupTotal = [int]$timingSummary.Groups['total'].Value
$period = Parse-Float $clockSummary.Groups['period'].Value
$freq = Parse-Float $clockSummary.Groups['freq'].Value
$req = Parse-Float $pathSummary.Groups['req'].Value
$delay = Parse-Float $pathSummary.Groups['delay'].Value
$logicDelay = Parse-Float $pathSummary.Groups['logic'].Value
$routeDelay = Parse-Float $pathSummary.Groups['route'].Value
$logicLevels = [int]$pathSummary.Groups['levels'].Value
$slack = [Math]::Round($req - $delay, 3)

$powerSummary = [regex]::Match($power, '\|\s*Total On-Chip Power \(W\)\s*\|\s*(?<total>\d+\.\d+)\s*\|.*?\|\s*Dynamic \(W\)\s*\|\s*(?<dynamic>\d+\.\d+)\s*\|.*?\|\s*Device Static \(W\)\s*\|\s*(?<static>\d+\.\d+)\s*\|.*?\|\s*Max Ambient \(C\)\s*\|\s*(?<ambient>\d+\.\d+)\s*\|.*?\|\s*Junction Temperature \(C\)\s*\|\s*(?<junction>\d+\.\d+)\s*\|.*?\|\s*Confidence Level\s*\|\s*(?<confidence>[A-Za-z]+)\s*\|', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$totalPower = Parse-Float $powerSummary.Groups['total'].Value
$dynamicPower = Parse-Float $powerSummary.Groups['dynamic'].Value
$staticPower = Parse-Float $powerSummary.Groups['static'].Value
$ambientTemp = Parse-Float $powerSummary.Groups['ambient'].Value
$junctionTemp = Parse-Float $powerSummary.Groups['junction'].Value
$confidence = $powerSummary.Groups['confidence'].Value

$components = @(
  [pscustomobject]@{ Name = "Clocks"; Value = 0.003 },
  [pscustomobject]@{ Name = "Slice Logic"; Value = 0.009 },
  [pscustomobject]@{ Name = "Signals"; Value = 0.010 },
  [pscustomobject]@{ Name = "Block RAM"; Value = 0.007 }
)

function New-Canvas([int]$w, [int]$h) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $g.Clear([System.Drawing.Color]::White)
  return @{ Bitmap = $bmp; Graphics = $g }
}

function Save-Canvas($canvas, [string]$path) {
  $canvas.Bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $canvas.Graphics.Dispose()
  $canvas.Bitmap.Dispose()
}

$timingCanvas = New-Canvas 1400 760
$g = $timingCanvas.Graphics
$titleFont = New-Font 34 ([System.Drawing.FontStyle]::Bold)
$subFont = New-Font 20
$labelFont = New-Font 18 ([System.Drawing.FontStyle]::Bold)
$smallFont = New-Font 16
$black = [System.Drawing.Brushes]::Black
Draw-Text $g "Final Single-SISO Timing Summary" $titleFont $black 40 24
Draw-Text $g "Extracted from routed Vivado timing summary" $subFont ([System.Drawing.Brushes]::DimGray) 42 70

$axisX = 70; $axisY = 165; $axisW = 840; $axisH = 76
$outlinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 2)
$logicBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(87, 132, 213))
$routeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(244, 177, 76))
$slackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(111, 180, 90))
Draw-Text $g "Critical Setup Path vs Clock Budget" $labelFont $black $axisX ($axisY - 38)
Draw-Box $g $outlinePen $null $axisX $axisY $axisW $axisH

$logicW = [int]($axisW * ($logicDelay / $req))
$routeW = [int]($axisW * ($routeDelay / $req))
$slackW = [int]($axisW * (($req - $delay) / $req))
$g.FillRectangle($logicBrush, $axisX, $axisY, $logicW, $axisH)
$g.FillRectangle($routeBrush, $axisX + $logicW, $axisY, $routeW, $axisH)
$g.FillRectangle($slackBrush, $axisX + $logicW + $routeW, $axisY, $slackW, $axisH)

for ($i = 0; $i -le 4; $i++) {
  $tickX = $axisX + ($axisW * $i / 4.0)
  $g.DrawLine($outlinePen, $tickX, ($axisY + $axisH), $tickX, ($axisY + $axisH + 10))
  Draw-CenteredText $g ("{0:N0} ns" -f ($req * $i / 4.0)) $smallFont $black ($tickX - 40) ($axisY + $axisH + 12) 80 24
}
Draw-CenteredText $g ("Logic {0:N3} ns" -f $logicDelay) $smallFont $black $axisX ($axisY + 20) $logicW 20
Draw-CenteredText $g ("Route {0:N3} ns" -f $routeDelay) $smallFont $black ($axisX + $logicW) ($axisY + 20) $routeW 20
Draw-CenteredText $g ("Slack {0:N3} ns" -f $slack) $smallFont $black ($axisX + $logicW + $routeW) ($axisY + 20) $slackW 20

Draw-MetricBox $g "Clock Period" ("{0:N3} ns" -f $period) 980 150 340 96
Draw-MetricBox $g "WNS / WHS" ("{0:N3} / {1:N3} ns" -f $wns, $whs) 980 270 340 96
Draw-MetricBox $g "Setup Endpoints" ("{0} / {1}" -f $setupFail, $setupTotal) 980 390 340 96
Draw-MetricBox $g "Clock / Logic" ("{0:N1} MHz, {1} levels" -f $freq, $logicLevels) 980 510 340 96

$legendY = 305
Draw-Text $g "Path composition:" $labelFont $black 70 $legendY
$legendItems = @(
  @{ Brush = $logicBrush; Text = "Logic delay: $logicDelay ns (45.5%)" },
  @{ Brush = $routeBrush; Text = "Route delay: $routeDelay ns (54.5%)" },
  @{ Brush = $slackBrush; Text = "Timing margin: $slack ns" }
)
$lx = 70; $ly = $legendY + 36
foreach ($item in $legendItems) {
  $g.FillRectangle($item.Brush, $lx, $ly, 24, 24)
  $g.DrawRectangle($outlinePen, $lx, $ly, 24, 24)
  Draw-Text $g $item.Text $smallFont $black ($lx + 36) ($ly + 2)
  $ly += 38
}
Draw-Text $g "Constraint status: All user specified timing constraints are met at 25 MHz." $labelFont $black 70 480
Draw-Text $g "Critical setup path requirement = 40.000 ns; measured path delay = 37.849 ns." $smallFont $black 70 515
Draw-Text $g "The routed critical path is dominated by route delay rather than logic delay." $smallFont $black 70 542

Save-Canvas $timingCanvas (Join-Path $figDir "single_siso_timing_visual.png")

$powerCanvas = New-Canvas 1400 760
$g = $powerCanvas.Graphics
Draw-Text $g "Final Single-SISO Power Summary" $titleFont $black 40 24
Draw-Text $g "Extracted from routed Vivado power report" $subFont ([System.Drawing.Brushes]::DimGray) 42 70

$barX = 90; $barY = 180; $barW = 240; $barH = 400
Draw-Text $g "Total on-chip power" $labelFont $black $barX ($barY - 36)
Draw-Box $g $outlinePen $null $barX $barY $barW $barH
$staticH = [int]($barH * ($staticPower / $totalPower))
$dynamicH = $barH - $staticH
$staticBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 150, 150))
$dynamicBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(77, 153, 242))
$g.FillRectangle($staticBrush, $barX, $barY, $barW, $staticH)
$g.FillRectangle($dynamicBrush, $barX, ($barY + $staticH), $barW, $dynamicH)
Draw-CenteredText $g ("Static`n{0:N3} W" -f $staticPower) $labelFont $black $barX $barY $barW $staticH
Draw-CenteredText $g ("Dynamic`n{0:N3} W" -f $dynamicPower) $labelFont $black $barX ($barY + $staticH) $barW $dynamicH
Draw-CenteredText $g ("Total = {0:N3} W" -f $totalPower) $labelFont $black ($barX - 20) ($barY + $barH + 20) ($barW + 40) 28

$compX = 470; $compY = 185
Draw-Text $g "Dynamic power by component" $labelFont $black $compX ($compY - 40)
$maxComp = ($components | Measure-Object -Property Value -Maximum).Maximum
$scale = 500 / $maxComp
$colors = @(
  [System.Drawing.Color]::FromArgb(87,132,213),
  [System.Drawing.Color]::FromArgb(244,177,76),
  [System.Drawing.Color]::FromArgb(111,180,90),
  [System.Drawing.Color]::FromArgb(192,80,77)
)
for ($i = 0; $i -lt $components.Count; $i++) {
  $cy = $compY + $i * 78
  $name = $components[$i].Name
  $value = [double]$components[$i].Value
  Draw-Text $g $name $smallFont $black $compX $cy
  $bw = [int]($value * $scale)
  $brush = New-Object System.Drawing.SolidBrush($colors[$i])
  Draw-Box $g $outlinePen $brush ($compX + 150) ($cy - 2) $bw 34
  Draw-Text $g ("{0:N3} W" -f $value) $smallFont $black ($compX + 165 + $bw) ($cy + 3)
}

Draw-MetricBox $g "Junction / Ambient" ("{0:N1} / {1:N1} C" -f $junctionTemp, $ambientTemp) 970 150 320 96
Draw-MetricBox $g "Static / Dynamic" ("{0:N3} / {1:N3} W" -f $staticPower, $dynamicPower) 970 270 320 96
Draw-MetricBox $g "Confidence Level" $confidence 970 390 320 96
Draw-MetricBox $g "Top Hierarchy Power" "turbo_decoder_top = 0.028 W" 970 510 320 96

Draw-Text $g "Key observations:" $labelFont $black 470 555
Draw-Text $g "Static power dominates the total budget (0.093 W out of 0.121 W)." $smallFont $black 470 592
Draw-Text $g "Among dynamic contributors, signals and slice logic dominate, while BRAM stays moderate." $smallFont $black 470 620
Draw-Text $g "The report confidence is low because Vivado did not receive simulation activity for most internal nodes." $smallFont $black 470 648

Save-Canvas $powerCanvas (Join-Path $figDir "single_siso_power_visual.png")

