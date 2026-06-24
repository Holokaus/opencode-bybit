param([string]$InputDir=".",[string]$OutputDir=".")
$ErrorActionPreference="Stop"
$logFile=Join-Path $OutputDir "forensic_log.txt"
function Log{param($m)$ts=(Get-Date -Format 'HH:mm:ss.fff');$l="[$ts] $m";Add-Content -Path $logFile -Value $l;Write-Output $l}

Log "=== FORENSIC AUDIT STARTED ==="
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue

$k=Import-Csv (Join-Path $InputDir "SOLUSDT-FUTURES-2021-2026-30m.csv")
$n=$k.Count
$h=[double[]]::new($n);$l2=[double[]]::new($n);$c=[double[]]::new($n);$v=[double[]]::new($n);$o=[double[]]::new($n)
for($i=0;$i-lt$n;$i++){
  $h[$i]=[double]$k[$i].High;$l2[$i]=[double]$k[$i].Low
  $o[$i]=[double]$k[$i].Open;$c[$i]=[double]$k[$i].Close;$v[$i]=[double]$k[$i].Volume
}
$dl=New-Object 'Collections.Generic.List[string]'
foreach($r in $k){$dl.Add($r.Date)}
$dates=$dl.ToArray()
Log "Data loaded: $n bars"

$sig=Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $c $h $l2 $v $n

# ===== AUDIT 1: LATENCY =====
Log "=== AUDIT 1: LATENCY TRACE ==="
$sampleSize=100
$sampleOut=New-Object 'Collections.Generic.List[PSObject]'

$siList=New-Object 'Collections.Generic.List[int]'
for($si=100;$si-lt$sig.Length;$si++){if($sig[$si]){$siList.Add($si)}}
$allSi=$siList.ToArray()
Log "Total signal bars: $($allSi.Length)"

# Take first 100 signals for sample
$sampleCount=[Math]::Min($sampleSize,$allSi.Length)
$sampleIndices=$allSi[0..($sampleCount-1)]

foreach($lat in @(0,1,2,3)){
  foreach($si in $sampleIndices){
    $ei=$si+$lat
    $ex=$ei+5
    if($ex-ge$n){continue}
    $ret=($c[$ex]-$c[$ei])/$c[$ei]*100
    $sampleOut.Add([PSCustomObject]@{
      Latency="$lat bar(s)";
      SignalIdx=$si;
      SignalDate=$dates[$si];
      EntryIdx=$ei;
      EntryDate=$dates[$ei];
      ExitIdx=$ex;
      ExitDate=$dates[$ex];
      EntryPrice=[Math]::Round($c[$ei],4);
      ExitPrice=[Math]::Round($c[$ex],4);
      ReturnPct=[Math]::Round($ret,2);
      WinFlag=if($ret-gt0){"WIN"}else{"LOSS"}
    })
  }
}

$latCsv=Join-Path $OutputDir "latency_trade_samples.csv"
$sampleOut|Export-Csv -Path $latCsv -NoTypeInformation
Log "Saved $latCsv"

# Compute aggregate metrics per latency mode for ALL signals
Log "Computing aggregate metrics per latency mode..."
foreach($lat in @(0,1,2,3)){
  $lr2=New-Object 'Collections.Generic.List[double]'
  $winC=0;$lossC=0
  for($si=100;$si-lt$sig.Length;$si++){
    if($sig[$si]){
      $ei=$si+$lat;$ex=$ei+5
      if($ex-lt$n){
        $ret=($c[$ex]-$c[$ei])/$c[$ei]*100
        $lr2.Add($ret)
        if($ret-gt0){$winC++}else{$lossC++}
      }
    }
  }
  $total=$lr2.Count
  $avg=if($total-gt0){($lr2|Measure -Average).Average}else{0}
  $g=($lr2|?{$_-gt0}|Measure -Sum).Sum
  $ls=($lr2|?{$_-lt0}|Measure -Sum).Sum
  $pf=if($ls-ne0){[Math]::Abs($g/$ls)}else{999}
  Log ("  Latency " + $lat + ": trades=" + $total + " wins=" + $winC + " losses=" + $lossC + " avg=" + [Math]::Round($avg,4) + " PF=" + [Math]::Round($pf,4))
}

# ===== AUDIT 2: WALK-FORWARD SPLITS =====
Log "=== AUDIT 2: WALK-FORWARD SPLITS ==="
$fsw=10000;$tsw=20000;$nfw=[Math]::Floor(($n-$tsw)/$fsw)
Log ("Params: fsw=" + $fsw + " tsw=" + $tsw + " nfw=" + $nfw)

$wfRows=New-Object 'Collections.Generic.List[PSObject]'
# DEBUG: Check if $te already exists
if(Test-Path Variable:te){Write-Host ("[DEBUG] te ALREADY EXISTS with value: " + $te)}else{Write-Host "[DEBUG] te does not exist yet"}
$testExpr = 20000 + 0 * 10000
Write-Host ("[DEBUG] Direct computation 20000 + 0 * 10000 = " + $testExpr)
for($f=0;$f-lt$nfw;$f++){
  Write-Host ("[BEFORE] f=" + $f + " tsw=" + $tsw + " fsw=" + $fsw + " (tsw+f*fsw)_literal=" + ($tsw+$f*$fsw))
  $te=$tsw+$f*$fsw
  Write-Host ("[AFTER] te=" + $te + " | check1=" + ($tsw+$f*$fsw) + " check2=" + (20000+$f*10000) + " check3=" + ($tsw+0*$fsw))
  $ts=$te
  $tE=[Math]::Min($ts+$fsw,$n)
  
  $trainStart=0
  $trainEnd=$te-1
  $testStart=$ts
  $testEnd=$tE-1
  
  # DIRECT WRITE INSTEAD OF LOG
  $msg = "  Fold " + ($f+1) + ": te=" + $te + " te-1=" + ($te-1) + " train=[0.." + $trainEnd + "] test=[" + $testStart + ".." + $testEnd + "]"
  Write-Host $msg
  
  # Calculate overlap
  $overlapBars=0
  if($testStart-le$trainEnd){
    $overlapStart=$testStart
    $overlapEnd=[Math]::Min($trainEnd,$testEnd)
    $overlapBars=$overlapEnd-$overlapStart+1
  }
  
  $hasOverlap=if($overlapBars-gt0){"YES"}else{"NO"}
  
  Log ("  Fold " + ($f+1) + ": te=" + $te + " train=[" + $trainStart + ".." + $trainEnd + "] test=[" + $testStart + ".." + $testEnd + "] overlap=" + $overlapBars + " bars -> " + $hasOverlap)
  
  $wfRows.Add([PSCustomObject]@{
    Fold=$f+1;
    TrainStart=$trainStart;
    TrainEnd=$trainEnd;
    TestStart=$testStart;
    TestEnd=$testEnd;
    OverlapBars=$overlapBars;
    HasOverlap=$hasOverlap
  })
}

$wfCsv=Join-Path $OutputDir "walkforward_fold_audit.csv"
$wfRows|Export-Csv -Path $wfCsv -NoTypeInformation
Log "Saved $wfCsv"

# Also check what signal computation would look like for each fold
Log "Checking signal computation boundaries..."
for($f=0;$f-lt$nfw;$f++){
  $te=$tsw+$f*$fsw
  $ts=$te
  $tE=[Math]::Min($ts+$fsw,$n)
  
  # Training signal: computed on bars 0..(te-1), length = te bars
  $trainLen=$te
  $trainFirstIdx=0
  $trainLastIdx=$te-1
  $trainActualEnd=$te-1
  
  # Test signal: computed on bars ts..(tE-1), length = tlen bars
  $tlen=$tE-$ts
  $testFirstIdx=$ts
  $testLastIdx=$tE-1
  
  Log ("  Fold " + ($f+1) + " (f=" + $f + "): te=" + $te + " ts=" + $ts + " tE=" + $tE)
  Log ("    Training signal on bars 0.." + $trainActualEnd + " (" + $trainLen + " bars)")
  Log ("    Test signal on bars " + $testFirstIdx + ".." + $testLastIdx + " (" + $tlen + " bars)")
  
  # Check if test bar range overlaps with training
  if($testFirstIdx -le $trainActualEnd){
    Log ("    *** OVERLAP: Test bar " + $testFirstIdx + " <= Train bar " + $trainActualEnd)
  } else {
    Log ("    *** CLEAN: Test bar " + $testFirstIdx + " > Train bar " + $trainActualEnd)
  }
}

Log "=== FORENSIC AUDIT COMPLETE ==="
