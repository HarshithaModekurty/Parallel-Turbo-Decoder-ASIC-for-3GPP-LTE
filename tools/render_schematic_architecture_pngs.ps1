
Add-Type -AssemblyName System.Drawing

$BLACK = [System.Drawing.Color]::Black
$WHITE = [System.Drawing.Color]::White

function New-Font($size, $bold=$false) {
    if ($bold) { return New-Object System.Drawing.Font('Segoe UI', $size, [System.Drawing.FontStyle]::Bold) }
    return New-Object System.Drawing.Font('Segoe UI', $size, [System.Drawing.FontStyle]::Regular)
}

function Draw-Text($g, $text, $x, $y, $size=11, $bold=$false) {
    $font = New-Font $size $bold
    $brush = New-Object System.Drawing.SolidBrush($BLACK)
    $g.DrawString($text, $font, $brush, $x, $y)
    $font.Dispose(); $brush.Dispose()
}

function Draw-CenteredText($g, $text, $rect, $size=10, $bold=$false) {
    $font = New-Font $size $bold
    $brush = New-Object System.Drawing.SolidBrush($BLACK)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($text, $font, $brush, $rect, $fmt)
    $font.Dispose(); $brush.Dispose(); $fmt.Dispose()
}

function Draw-Box($g, $x, $y, $w, $h, $title, $body='') {
    $pen = New-Object System.Drawing.Pen($BLACK, 2)
    $brush = New-Object System.Drawing.SolidBrush($WHITE)
    $g.FillRectangle($brush, $x, $y, $w, $h)
    $g.DrawRectangle($pen, $x, $y, $w, $h)
    if ($title -ne '') {
        Draw-Text $g $title ($x + 8) ($y + 6) 10 $true
        $g.DrawLine($pen, $x, $y + 28, $x + $w, $y + 28)
    }
    if ($body -ne '') {
        Draw-Text $g $body ($x + 8) ($y + 34) 9 $false
    }
    $pen.Dispose(); $brush.Dispose()
}

function Draw-DashedGroup($g, $x, $y, $w, $h, $title) {
    $pen = New-Object System.Drawing.Pen($BLACK, 1.5)
    $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $g.DrawRectangle($pen, $x, $y, $w, $h)
    Draw-Text $g $title ($x + 8) ($y - 22) 12 $true
    $pen.Dispose()
}

function Draw-Arrow($g, $x1, $y1, $x2, $y2, $label='') {
    $pen = New-Object System.Drawing.Pen($BLACK, 2)
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
    $g.DrawLine($pen, $x1, $y1, $x2, $y2)
    if ($label -ne '') { Draw-Text $g $label ((($x1+$x2)/2)+4) ((($y1+$y2)/2)-10) 9 $false }
    $pen.Dispose()
}

function Draw-Bus($g, $x1, $y1, $x2, $y2, $label='') {
    $pen = New-Object System.Drawing.Pen($BLACK, 4)
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
    $g.DrawLine($pen, $x1, $y1, $x2, $y2)
    if ($label -ne '') { Draw-Text $g $label ((($x1+$x2)/2)+4) ((($y1+$y2)/2)-12) 9 $false }
    $pen.Dispose()
}

function Draw-Mux($g, $x, $y, $w, $h, $label='MUX') {
    $pts = @(
        [System.Drawing.Point]::new($x, $y + 8),
        [System.Drawing.Point]::new($x + $w - 12, $y),
        [System.Drawing.Point]::new($x + $w, $y + $h/2),
        [System.Drawing.Point]::new($x + $w - 12, $y + $h),
        [System.Drawing.Point]::new($x, $y + $h - 8),
        [System.Drawing.Point]::new($x + 10, $y + $h/2)
    )
    $pen = New-Object System.Drawing.Pen($BLACK, 2)
    $brush = New-Object System.Drawing.SolidBrush($WHITE)
    $g.FillPolygon($brush, $pts)
    $g.DrawPolygon($pen, $pts)
    Draw-CenteredText $g $label ([System.Drawing.RectangleF]::new($x, $y, $w, $h)) 9 $true
    $pen.Dispose(); $brush.Dispose()
}

function Draw-Adder($g, $x, $y, $w, $h, $label='+') {
    $pts = @(
        [System.Drawing.Point]::new($x, $y + 8),
        [System.Drawing.Point]::new($x + $w - 18, $y),
        [System.Drawing.Point]::new($x + $w, $y + $h/2),
        [System.Drawing.Point]::new($x + $w - 18, $y + $h),
        [System.Drawing.Point]::new($x, $y + $h - 8),
        [System.Drawing.Point]::new($x + 12, $y + $h/2)
    )
    $pen = New-Object System.Drawing.Pen($BLACK, 2)
    $brush = New-Object System.Drawing.SolidBrush($WHITE)
    $g.FillPolygon($brush, $pts)
    $g.DrawPolygon($pen, $pts)
    Draw-CenteredText $g $label ([System.Drawing.RectangleF]::new($x, $y, $w, $h)) 12 $true
    $pen.Dispose(); $brush.Dispose()
}

function Draw-CompareSwap($g, $x, $y, $w, $h, $label='cmp/swap') {
    $pts = @(
        [System.Drawing.Point]::new($x, $y + 10),
        [System.Drawing.Point]::new($x + $w/2 - 18, $y),
        [System.Drawing.Point]::new($x + $w/2, $y + $h/2 - 10),
        [System.Drawing.Point]::new($x + $w/2 + 18, $y),
        [System.Drawing.Point]::new($x + $w, $y + 10),
        [System.Drawing.Point]::new($x + $w - 18, $y + $h/2),
        [System.Drawing.Point]::new($x + $w, $y + $h - 10),
        [System.Drawing.Point]::new($x + $w/2 + 18, $y + $h),
        [System.Drawing.Point]::new($x + $w/2, $y + $h/2 + 10),
        [System.Drawing.Point]::new($x + $w/2 - 18, $y + $h),
        [System.Drawing.Point]::new($x, $y + $h - 10),
        [System.Drawing.Point]::new($x + 18, $y + $h/2)
    )
    $pen = New-Object System.Drawing.Pen($BLACK, 2)
    $brush = New-Object System.Drawing.SolidBrush($WHITE)
    $g.FillPolygon($brush, $pts)
    $g.DrawPolygon($pen, $pts)
    Draw-CenteredText $g $label ([System.Drawing.RectangleF]::new($x, $y, $w, $h)) 9 $true
    $pen.Dispose(); $brush.Dispose()
}

function Draw-Register($g, $x, $y, $w, $h, $label='REG') {
    Draw-Box $g $x $y $w $h $label ''
    $pen = New-Object System.Drawing.Pen($BLACK, 1.5)
    $g.DrawLine($pen, $x+10, $y+$h-12, $x+24, $y+$h-12)
    $g.DrawLine($pen, $x+24, $y+$h-12, $x+24, $y+$h-24)
    $pen.Dispose()
}

function Render($path, $title, $drawer, $w=2200, $h=1400) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear($WHITE)
    Draw-Text $g $title 20 18 20 $true
    & $drawer $g
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# more content appended later by python placeholders
New-Item -ItemType Directory -Force 'architecture_exports/parallel8_top/internal_units' | Out-Null
New-Item -ItemType Directory -Force 'architecture_exports/turbo_iteration_ctrl' | Out-Null

Render 'architecture_exports/batcher_master_slave/BATCHER_MASTER_ARCHITECTURE.png' 'batcher_master: structural architecture' {
param($g)
Draw-DashedGroup $g 40 110 650 600 'address / tag setup'
Draw-Box $g 70 170 250 110 'addr_in' '8 packed address fields'
Draw-Box $g 360 170 290 170 'unpack + tag init' 'addr_v(i) = addr_in slice i`nlane_v(i) = i`nworking arrays for sorting'
Draw-Bus $g 320 225 360 225 'addr slices'
Draw-DashedGroup $g 740 110 980 600 '6-stage compare-swap sorting network'
$x = 790; $dx = 150; $y1 = 180
$labels = @('S0','S1','S2','S3','S4','S5')
for($i=0; $i -lt 6; $i++){
  Draw-CompareSwap $g ($x + $dx*$i) $y1 90 70 $labels[$i]
}
Draw-Text $g '(0,1)(2,3)(4,5)(6,7)' 770 260 8 $false
Draw-Text $g '(0,2)(1,3)(4,6)(5,7)' 915 260 8 $false
Draw-Text $g '(1,2)(5,6)' 1095 260 8 $false
Draw-Text $g '(0,4)(1,5)(2,6)(3,7)' 1190 260 8 $false
Draw-Text $g '(2,4)(3,5)' 1385 260 8 $false
Draw-Text $g '(1,2)(3,4)(5,6)' 1490 260 8 $false
Draw-Arrow $g 650 225 790 215 'addr_v/lane_v'
for($i=0; $i -lt 5; $i++) { Draw-Arrow $g (880 + 150*$i) 215 (940 + 150*$i) 215 '' }
Draw-Text $g '19 total compare-swap cells' 1030 420 11 $true
Draw-Text $g 'each cell = comparator + address mux pair + lane-tag mux pair + ctrl bit' 850 455 10 $false
Draw-DashedGroup $g 1760 110 380 600 'packed outputs'
Draw-Box $g 1800 180 300 110 'addr_sorted' 'ascending address slots'
Draw-Box $g 1800 340 300 110 'perm_out' 'sorted slot -> original lane'
Draw-Box $g 1800 500 300 110 'ctrl_out[18:0]' 'per-cell swap history'
Draw-Bus $g 1640 215 1800 235 'sorted addr/tag'
Draw-Arrow $g 1640 215 1800 395 'lane tags'
Draw-Arrow $g 1640 215 1800 555 'ctrl bits'
}

Render 'architecture_exports/batcher_master_slave/BATCHER_MASTER_DATAPATH.png' 'batcher_master: datapath view' {
param($g)
Draw-Text $g 'addr path' 70 90 12 $true
Draw-Bus $g 70 130 320 130 'addr_in[7:0]'
Draw-CompareSwap $g 360 90 120 80 'cmp0'
Draw-CompareSwap $g 520 90 120 80 'cmp1'
Draw-CompareSwap $g 680 90 120 80 'cmp2'
Draw-CompareSwap $g 840 90 120 80 'cmp3'
Draw-Arrow $g 320 130 360 130 ''
Draw-Arrow $g 480 130 520 130 ''
Draw-Arrow $g 640 130 680 130 ''
Draw-Arrow $g 800 130 840 130 ''
Draw-Bus $g 960 130 1180 130 'stage outputs'
Draw-Text $g 'lane-tag path mirrors the same swaps' 70 250 12 $true
Draw-Bus $g 70 290 320 290 'lane_v = 0..7'
Draw-Mux $g 380 250 90 80 'swap'
Draw-Mux $g 540 250 90 80 'swap'
Draw-Mux $g 700 250 90 80 'swap'
Draw-Mux $g 860 250 90 80 'swap'
Draw-Arrow $g 320 290 380 290 ''
Draw-Arrow $g 470 290 540 290 ''
Draw-Arrow $g 630 290 700 290 ''
Draw-Arrow $g 790 290 860 290 ''
Draw-Bus $g 950 290 1180 290 'perm data'
Draw-Box $g 1280 120 520 220 'stage schedule' 'S0:(0,1)(2,3)(4,5)(6,7)`nS1:(0,2)(1,3)(4,6)(5,7)`nS2:(1,2)(5,6)`nS3:(0,4)(1,5)(2,6)(3,7)`nS4:(2,4)(3,5)`nS5:(1,2)(3,4)(5,6)'
Draw-Text $g 'full datapath = addr comparisons + synchronized tag swaps through 6 stages' 1280 380 11 $false
}

Render 'architecture_exports/batcher_master_slave/BATCHER_MASTER_CONTROL.png' 'batcher_master: control view' {
param($g)
Draw-Box $g 100 130 300 120 'compare logic' '19 greater-than comparisons over selected address pairs'
Draw-Mux $g 470 140 120 80 'swap en'
Draw-Mux $g 650 140 120 80 'swap en'
Draw-Box $g 840 130 360 120 'control fanout' 'same compare result drives:`n1. address swap mux select`n2. lane-tag swap mux select`n3. ctrl_out bit'
Draw-Arrow $g 400 190 470 180 'cmp'
Draw-Arrow $g 590 180 650 180 ''
Draw-Arrow $g 770 180 840 190 'selects'
Draw-Box $g 300 340 680 180 'meaning' 'There is no FSM.`nControl is local and combinational.`nEach compare-swap cell generates one boolean decision.`nThat decision both controls the datapath and becomes structural trace output.'
}

Render 'architecture_exports/batcher_master_slave/BATCHER_SLAVE_ARCHITECTURE.png' 'batcher_slave: structural architecture' {
param($g)
Draw-DashedGroup $g 50 110 560 540 'unpack / decode'
Draw-Box $g 80 170 220 110 'data_in' 'packed payload lanes'
Draw-Box $g 80 330 220 110 'perm_in' 'packed lane indices'
Draw-Box $g 340 150 230 150 'input unpack' 'in_v(i) = data slice i`nout_v(i) = 0'
Draw-Box $g 340 340 230 120 'perm decode' 'perm_i = to_integer(...)`nbounds check: 0 <= perm_i < G_P'
Draw-Arrow $g 300 225 340 225 'lane data'
Draw-Arrow $g 300 385 340 385 'perm'
Draw-DashedGroup $g 670 110 760 540 'permutation router core'
for($i=0; $i -lt 4; $i++){
  Draw-Mux $g (720 + 170*$i) 200 110 80 ('slot'+$i)
  Draw-Mux $g (720 + 170*$i) 350 110 80 ('slot'+($i+4))
}
Draw-Text $g 'each slot router chooses forward or reverse assignment' 870 470 11 $false
Draw-Arrow $g 570 225 720 240 'data+perm'
Draw-Arrow $g 570 385 720 390 ''
Draw-DashedGroup $g 1480 110 380 540 'packed output'
Draw-Box $g 1520 240 300 130 'repack out_v[]' 'd_tmp <= out_v lane slices`ndata_out <= d_tmp'
Draw-Box $g 1520 420 300 110 'mode' 'G_REVERSE=false: sorted -> lane order`nG_REVERSE=true: lane -> sorted order'
Draw-Bus $g 1360 280 1520 305 'out_v[]'
}
Render 'architecture_exports/batcher_master_slave/BATCHER_SLAVE_DATAPATH.png' 'batcher_slave: datapath view' {
param($g)
Draw-Bus $g 80 150 300 150 'data_in'
Draw-Box $g 340 100 240 110 'slice lanes' 'in_v(0..P-1)'
Draw-Arrow $g 300 150 340 155 ''
Draw-Bus $g 80 320 300 320 'perm_in'
Draw-Box $g 340 270 240 110 'decode indices' 'perm_i per slot'
Draw-Arrow $g 300 320 340 325 ''
Draw-Mux $g 690 120 120 80 'forward'
Draw-Mux $g 690 290 120 80 'reverse'
Draw-Arrow $g 580 155 690 160 'in_v(slot)'
Draw-Arrow $g 580 325 690 330 'in_v(perm_i)'
Draw-Box $g 910 180 420 150 'cross-lane write array' 'out_v(perm_i) = in_v(slot)`nor`nout_v(slot) = in_v(perm_i)'
Draw-Arrow $g 810 160 910 220 ''
Draw-Arrow $g 810 330 910 260 ''
Draw-Bus $g 1330 255 1540 255 'out_v[] -> data_out'
}

Render 'architecture_exports/batcher_master_slave/BATCHER_SLAVE_CONTROL.png' 'batcher_slave: control view' {
param($g)
Draw-Box $g 120 150 250 120 'slot loop (conceptual)' 'for slot in 0..G_P-1'
Draw-Box $g 450 150 250 120 'perm bounds comparator' '0 <= perm_i < G_P'
Draw-Mux $g 820 150 120 80 'mode'
Draw-Box $g 1020 150 420 120 'write-select control' 'choose destination index and source index`naccording to G_REVERSE'
Draw-Arrow $g 370 210 450 210 ''
Draw-Arrow $g 700 210 820 190 'valid perm'
Draw-Arrow $g 940 190 1020 210 'select'
Draw-Box $g 300 360 820 150 'meaning' 'Control is still combinational, not sequential hardware state.`nThe decisions are: decode perm, check valid range, choose forward or reverse routing.'
}

Render 'architecture_exports/batcher_master_slave/internal_units/BATCHER_MASTER_FUNCTIONAL_UNITS.png' 'batcher_master: internal functional units' {
param($g)
Draw-Box $g 110 150 260 150 'unit A' 'unpack 8 address slices`ninitialize lane tags 0..7'
Draw-CompareSwap $g 470 180 160 100 'unit B'
Draw-Text $g 'compare-swap cell' 485 295 10 $false
Draw-Box $g 740 150 280 150 'unit C' 'replicate compare-swap cell into 6 stages / 19 cells'
Draw-Box $g 1130 150 280 150 'unit D' 'pack final addr_v, lane_v, c_tmp'
Draw-Arrow $g 370 225 470 230 ''
Draw-Arrow $g 630 230 740 225 ''
Draw-Arrow $g 1020 225 1130 225 ''
}

Render 'architecture_exports/batcher_master_slave/internal_units/BATCHER_MASTER_COMPARE_SWAP_CELL.png' 'batcher_master: compare-swap primitive' {
param($g)
Draw-Bus $g 70 170 240 170 'addr_L'
Draw-Bus $g 70 250 240 250 'addr_R'
Draw-Bus $g 70 370 240 370 'lane_L'
Draw-Bus $g 70 450 240 450 'lane_R'
Draw-CompareSwap $g 320 170 180 120 'cmp'
Draw-Mux $g 590 150 120 80 'addr'
Draw-Mux $g 590 250 120 80 'addr'
Draw-Mux $g 590 350 120 80 'lane'
Draw-Mux $g 590 450 120 80 'lane'
Draw-Arrow $g 240 170 320 205 ''
Draw-Arrow $g 240 250 320 255 ''
Draw-Arrow $g 240 370 320 235 ''
Draw-Arrow $g 240 450 320 285 ''
Draw-Arrow $g 500 230 590 190 'cmp'
Draw-Arrow $g 500 230 590 290 'cmp'
Draw-Arrow $g 500 230 590 390 'cmp'
Draw-Arrow $g 500 230 590 490 'cmp'
Draw-Bus $g 710 190 900 190 'addr_L'''
Draw-Bus $g 710 290 900 290 'addr_R'''
Draw-Bus $g 710 390 900 390 'lane_L'''
Draw-Bus $g 710 490 900 490 'lane_R'''
Draw-Box $g 1010 210 220 120 'ctrl_bit' 'same cmp result exported'
Draw-Arrow $g 500 230 1010 270 'cmp'
}

Render 'architecture_exports/batcher_master_slave/internal_units/BATCHER_MASTER_SORTING_NETWORK.png' 'batcher_master: 6-stage network' {
param($g)
$xs = @(120, 320, 520, 720, 920, 1120)
$stageText = @(
  'S0`n(0,1)`n(2,3)`n(4,5)`n(6,7)',
  'S1`n(0,2)`n(1,3)`n(4,6)`n(5,7)',
  'S2`n(1,2)`n(5,6)',
  'S3`n(0,4)`n(1,5)`n(2,6)`n(3,7)',
  'S4`n(2,4)`n(3,5)',
  'S5`n(1,2)`n(3,4)`n(5,6)'
)
for($i=0;$i -lt 6;$i++){
  Draw-CompareSwap $g $xs[$i] 180 100 80 ('S'+$i)
  Draw-Text $g $stageText[$i] ($xs[$i]-10) 290 9 $false
  if($i -lt 5){ Draw-Arrow $g ($xs[$i]+100) 220 ($xs[$i+1]) 220 '' }
}
Draw-Bus $g 40 220 120 220 'init addr_v/lane_v'
Draw-Bus $g 1220 220 1390 220 'sorted result'
Draw-Text $g '19 compare-swap cells total' 500 420 12 $true
}

Render 'architecture_exports/batcher_master_slave/internal_units/BATCHER_SLAVE_FUNCTIONAL_UNITS.png' 'batcher_slave: internal functional units' {
param($g)
Draw-Box $g 120 170 240 130 'unit A' 'unpack input lanes'
Draw-Box $g 430 170 240 130 'unit B' 'decode perm_i + bounds check'
Draw-Mux $g 760 180 120 80 'route'
Draw-Box $g 960 170 240 130 'unit D' 'pack out_v -> data_out'
Draw-Arrow $g 360 235 430 235 ''
Draw-Arrow $g 670 235 760 220 ''
Draw-Arrow $g 880 220 960 235 ''
}

Render 'architecture_exports/batcher_master_slave/internal_units/BATCHER_SLAVE_SLOT_ROUTER_CELL.png' 'batcher_slave: slot router primitive' {
param($g)
Draw-Bus $g 60 170 240 170 'in_v(slot)'
Draw-Bus $g 60 260 240 260 'in_v(perm_i)'
Draw-Box $g 320 130 180 120 'perm_i' 'decoded lane index'
Draw-Box $g 320 300 180 100 'bounds cmp' '0<=perm_i<G_P'
Draw-Mux $g 580 190 120 80 'mode'
Draw-Box $g 800 160 280 140 'dest select' 'forward: out_v(perm_i)`nreverse: out_v(slot)'
Draw-Arrow $g 240 170 320 170 ''
Draw-Arrow $g 240 260 320 345 ''
Draw-Arrow $g 500 190 580 230 'valid+mode'
Draw-Arrow $g 700 230 800 230 ''
}

Render 'architecture_exports/batcher_master_slave/internal_units/BATCHER_SLAVE_PERMUTATION_NETWORK.png' 'batcher_slave: replicated permutation network' {
param($g)
for($i=0;$i -lt 8;$i++){
  $x = 90 + 210*$i
  Draw-Mux $g $x 220 110 80 ('slot'+$i)
  if($i -lt 7){ Draw-Arrow $g ($x+110) 260 ($x+210) 260 '' }
}
Draw-Bus $g 20 260 90 260 'in_v[]'
Draw-Bus $g 1770 260 1930 260 'out_v[]'
Draw-Text $g 'Eight identical slot-router cells operate in parallel over the same perm/data vector.' 420 430 12 $false
}
Render 'architecture_exports/turbo_iteration_ctrl/TURBO_ITERATION_CTRL_ARCHITECTURE.png' 'turbo_iteration_ctrl: structural architecture' {
param($g)
Draw-DashedGroup $g 80 110 760 520 'registered state'
Draw-Register $g 130 190 180 100 'state reg'
Draw-Register $g 130 350 180 100 'half_idx reg'
Draw-Register $g 130 500 180 100 'done_q reg'
Draw-DashedGroup $g 900 110 980 520 'combinational next-state / output logic'
Draw-Box $g 960 170 220 110 '==0 cmp' 'n_half_iter == 0'
Draw-Adder $g 1240 170 120 80 '+1'
Draw-Box $g 1420 160 240 110 '>= cmp' '(half_idx+1) >= n_half_iter'
Draw-Mux $g 1710 150 130 90 'ns mux'
Draw-Mux $g 1710 290 130 90 'idx mux'
Draw-Mux $g 1710 430 130 90 'done mux'
Draw-Box $g 1910 170 300 130 'output decode' 'st==RUN1`nst==RUN2`nOR/AND for last_half'
Draw-Arrow $g 310 240 960 225 'st'
Draw-Arrow $g 310 400 1240 210 'half_idx'
Draw-Arrow $g 1180 225 1240 210 ''
Draw-Arrow $g 1360 210 1420 210 ''
Draw-Arrow $g 1660 210 1710 195 ''
Draw-Arrow $g 1660 210 1710 335 ''
Draw-Arrow $g 310 240 1710 475 'state to done'
Draw-Arrow $g 1840 195 1910 220 ''
Draw-Arrow $g 1840 335 1910 250 ''
}

Render 'architecture_exports/turbo_iteration_ctrl/TURBO_ITERATION_CTRL_GATE_LEVEL.png' 'turbo_iteration_ctrl: near-gate-level view' {
param($g)
Draw-Box $g 120 160 180 110 'inputs' 'start`nn_half_iter`nsiso_done_1`nsiso_done_2'
Draw-Box $g 380 140 180 110 'state comparators' 'st==IDLE`nst==RUN1`nst==RUN2`nst==FINISH'
Draw-Box $g 380 320 180 110 'counter arithmetic' '+1 adder`n>= comparator'
Draw-Mux $g 650 150 120 80 'ns'
Draw-Mux $g 650 330 120 80 'idx'
Draw-Mux $g 650 500 120 80 'done'
Draw-Register $g 860 140 170 90 'state FF'
Draw-Register $g 860 320 170 90 'idx FF'
Draw-Register $g 860 500 170 90 'done FF'
Draw-Adder $g 1130 150 110 70 'OR'
Draw-Adder $g 1300 150 110 70 'AND'
Draw-Box $g 1490 130 270 120 'outputs' 'run_siso_1`nrun_siso_2`ndeint_phase`nlast_half`ndone'
Draw-Arrow $g 300 215 380 195 ''
Draw-Arrow $g 300 215 380 375 ''
Draw-Arrow $g 560 195 650 190 ''
Draw-Arrow $g 560 375 650 370 ''
Draw-Arrow $g 770 190 860 185 ''
Draw-Arrow $g 770 370 860 365 ''
Draw-Arrow $g 1030 185 1130 185 ''
Draw-Arrow $g 1240 185 1300 185 ''
Draw-Arrow $g 1410 185 1490 190 ''
}
Render 'architecture_exports/parallel8_top/TURBO_DECODER_TOP_PARALLEL8_ARCHITECTURE.png' 'turbo_decoder_top_parallel8_backup: structural architecture' {
param($g)
Draw-DashedGroup $g 40 90 360 860 'input / control side'
Draw-Box $g 70 150 300 120 'top inputs' 'start`nn_half_iter`nk_len,f1,f2`nin_valid,in_idx`nl_sys/par1/par2'
Draw-Register $g 90 330 150 90 'state + counters'
Draw-Adder $g 260 340 100 70 '+1'
Draw-Box $g 70 480 300 180 'scatter logic' 'seg_i = K/8`nlane_i = in_idx/seg_i`nrow_i = in_idx mod seg_i`npair_i = row_i>>1`none-hot lane select'
Draw-Box $g 70 720 300 140 'control checks' 'K>0`nK mod 8 = 0`nrun-edge detect`nissue_pair_idx compare'
Draw-DashedGroup $g 450 90 520 860 'memory shell'
Draw-Box $g 500 150 420 160 'systematic banks' 'sys_even_rd0/rd1`nsys_odd_rd0/rd1'
Draw-Box $g 500 360 420 140 'parity banks' 'par1_even/odd`npar2_even/odd'
Draw-Box $g 500 550 420 140 'extrinsic banks' 'ext_even_rd0/rd1`next_odd_rd0/rd1'
Draw-Box $g 500 740 420 140 'final posterior banks' 'final_even`nfinal_odd'
Draw-DashedGroup $g 1010 90 500 860 'run2 interleaver route fabric'
Draw-Box $g 1050 150 180 150 'row math' '2*pair_idx`n2*pair_idx+1`nrow_base>>1'
Draw-Box $g 1270 150 200 150 'QPP x2' '8 addresses`nrow_base`nrow_ok'
Draw-CompareSwap $g 1080 400 120 90 'BM0'
Draw-CompareSwap $g 1240 400 120 90 'BM1'
Draw-CompareSwap $g 1400 400 120 90 'BM2'
Draw-Text $g 'batcher masters = 19 compare-swap cells each' 1050 520 10 $false
Draw-Mux $g 1100 620 120 80 'sel'
Draw-Mux $g 1270 620 120 80 'slave'
Draw-Box $g 1050 760 420 120 'perm history' 'perm_even/odd_mem`nrow_base_even/odd_mem'
Draw-DashedGroup $g 1560 90 260 860 '8-lane decode core'
Draw-Box $g 1600 190 180 250 '8 x siso_maxlogmap' 'lane0..lane7`ncommon issue pair row`nparallel constituent decode'
Draw-Box $g 1600 540 180 140 'alignment checks' 'out_valid compare bank`nout_pair_idx compare bank`nall_done reduction'
Draw-DashedGroup $g 1860 90 300 860 'writeback + output'
Draw-Mux $g 1920 180 120 80 'wb'
Draw-Mux $g 1920 300 120 80 'unslave'
Draw-Box $g 1880 450 240 170 'write enables' 'ext_even/odd_wr*`nfinal_even/odd_wr*`nlast_half gating'
Draw-Register $g 1910 700 180 90 'serializer regs'
Draw-Adder $g 1910 820 100 70 '+1'
Draw-Arrow $g 370 390 450 230 'load'
Draw-Arrow $g 920 230 1050 225 'row reads'
Draw-Arrow $g 920 620 1100 660 'sorted rows'
Draw-Arrow $g 1510 660 1600 315 'lane feeds'
Draw-Arrow $g 1780 315 1920 220 'ext/post'
Draw-Arrow $g 1780 610 1920 340 'context'
}

Render 'architecture_exports/parallel8_top/TURBO_DECODER_TOP_PARALLEL8_DATAPATH.png' 'turbo_decoder_top_parallel8_backup: datapath schematic' {
param($g)
Draw-Bus $g 40 180 220 180 'scalar frame input'
Draw-Box $g 250 120 250 130 'scatter arithmetic' 'divide/mod/shift`none-hot lane select'
Draw-Box $g 250 320 250 130 'lane insertion' 'single_chan_lane()'
Draw-Arrow $g 220 180 250 185 ''
Draw-Arrow $g 375 250 375 320 ''
Draw-Bus $g 500 185 760 185 'load buses'
Draw-Box $g 800 120 230 130 'sys/par/ext/final BRAM banks' 'row memories'
Draw-Box $g 1100 120 240 130 'run1 feed muxes' 'sys + par1 + ext/zero'
Draw-Box $g 800 320 230 130 'run2 row math + QPP' 'even/odd row address generation'
Draw-Box $g 1100 320 240 130 'batcher route fabric' 'masters + physical row select + slaves'
Draw-Arrow $g 760 185 800 185 ''
Draw-Arrow $g 1030 185 1100 185 ''
Draw-Arrow $g 1030 385 1100 385 ''
Draw-Bus $g 1340 280 1540 280 'lane feed buses'
Draw-Box $g 1570 180 220 210 '8 x siso cores' 'parallel lane compute'
Draw-Arrow $g 1540 280 1570 285 ''
Draw-Bus $g 1790 285 1970 285 'ext/post'
Draw-Box $g 2000 160 180 120 'run1 direct write'
Draw-Box $g 2000 330 180 120 'run2 unslave'
Draw-Arrow $g 1970 285 2000 225 ''
Draw-Arrow $g 1970 285 2000 390 ''
Draw-Box $g 2220 240 220 150 'write-enable / dest mux' 'row_base parity + last_half gating'
Draw-Arrow $g 2180 225 2220 285 ''
Draw-Arrow $g 2180 390 2220 335 ''
Draw-Bus $g 2440 315 2620 315 'writes back to memories'
Draw-Box $g 2000 560 320 180 'serializer' 'idx/seg_bits`nidx mod seg_bits`nparity select final_even/final_odd'
}

Render 'architecture_exports/parallel8_top/TURBO_DECODER_TOP_PARALLEL8_CONTROL.png' 'turbo_decoder_top_parallel8_backup: control schematic' {
param($g)
Draw-Register $g 110 180 180 90 'FSM state'
Draw-Register $g 110 330 180 90 'half_idx'
Draw-Adder $g 350 340 100 70 '+1'
Draw-Box $g 510 170 240 110 'last-half cmp' '(half_idx+1)>=n_half_iter'
Draw-Mux $g 820 170 120 80 'next'
Draw-Arrow $g 290 225 510 205 'state'
Draw-Arrow $g 290 375 350 375 ''
Draw-Arrow $g 450 375 510 225 ''
Draw-Arrow $g 750 225 820 210 ''
Draw-Register $g 1050 180 180 90 'issue_pair_idx'
Draw-Adder $g 1280 190 100 70 '+1'
Draw-Box $g 1440 170 220 110 'pair_count cmp' 'issue_pair_idx == pair_count-1'
Draw-Mux $g 1720 170 120 80 'issue'
Draw-Arrow $g 1230 225 1280 225 ''
Draw-Arrow $g 1380 225 1440 225 ''
Draw-Arrow $g 1660 225 1720 210 ''
Draw-Register $g 1050 380 180 90 'feed_pipe regs'
Draw-Register $g 1050 560 180 90 'feed valid / is_odd regs'
Draw-Box $g 1440 380 280 110 'alignment compare bank' 'out_valid / out_pair_idx checks'
Draw-Adder $g 1790 390 100 70 'AND'
Draw-Box $g 1930 370 220 130 'serializer start / done' 'ser_issue_active`ndone_q'
Draw-Arrow $g 1230 425 1440 435 ''
Draw-Arrow $g 1720 435 1790 425 ''
Draw-Arrow $g 1890 425 1930 425 ''
}

Render 'architecture_exports/parallel8_top/internal_units/TURBO_DECODER_TOP_PARALLEL8_INTERNAL_ISOMORPHIC.png' 'parallel8 top: internal isomorphic schematic' {
param($g)
Draw-Box $g 80 140 260 170 'load primitives' 'divider`nmodulo`nshift`none-hot decode'
Draw-Box $g 400 140 260 170 'memory primitives' 'bank decode`nlocal row divide`nlane write mask`nread mux'
Draw-Box $g 720 140 260 170 'run2 route primitives' 'QPP adders`n19 compare-swap cells`nrow select muxes`nperm route muxes'
Draw-Box $g 1040 140 260 170 'lane feed primitives' 'run1/run2 muxes`nzero/ext apriori muxes`nout-of-range zero forcing'
Draw-Box $g 1360 140 260 170 'writeback primitives' 'row_base/2`nrow_base parity`nreverse unslave`nwrite-enable generation'
Draw-Box $g 1680 140 260 170 'serializer primitives' 'idx/seg_bits`nidx mod seg_bits`nparity select`nlast-symbol compare'
Draw-Arrow $g 340 225 400 225 ''
Draw-Arrow $g 660 225 720 225 ''
Draw-Arrow $g 980 225 1040 225 ''
Draw-Arrow $g 1300 225 1360 225 ''
Draw-Arrow $g 1620 225 1680 225 ''
}

Render 'architecture_exports/parallel8_top/internal_units/TURBO_DECODER_TOP_PARALLEL8_SCHEDULER_ISOMORPHIC.png' 'parallel8 top: scheduler isomorphic schematic' {
param($g)
Draw-Register $g 140 180 170 90 'run1_d/run2_d'
Draw-Mux $g 380 190 120 80 'edge'
Draw-Register $g 590 180 170 90 'issue regs'
Draw-Adder $g 840 190 100 70 '+1'
Draw-Mux $g 1010 190 120 80 'feed'
Draw-Register $g 1220 180 170 90 'feed_pipe'
Draw-Box $g 1450 170 220 110 'valid/pair comparators' 'alignment checks'
Draw-Adder $g 1740 190 100 70 'AND'
Draw-Register $g 1910 180 170 90 'ser regs'
Draw-Arrow $g 310 225 380 230 ''
Draw-Arrow $g 500 230 590 225 ''
Draw-Arrow $g 760 225 840 225 ''
Draw-Arrow $g 940 225 1010 230 ''
Draw-Arrow $g 1130 230 1220 225 ''
Draw-Arrow $g 1390 225 1450 225 ''
Draw-Arrow $g 1670 225 1740 225 ''
Draw-Arrow $g 1840 225 1910 225 ''
}
