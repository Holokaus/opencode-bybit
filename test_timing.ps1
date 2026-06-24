$start = Get-Date
$ErrorActionPreference = "Stop"
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force
Write-Host "Module: $(Get-Date)"

$InputDir = "$PSScriptRoot"
$klines = Import-Csv (Join-Path $InputDir "SOLUSDT-FUTURES-2021-2026-30m.csv")
Write-Host "CSV: $(Get-Date) count=$($klines.Count)"

$n = $klines.Count
$h = [double[]]::new($n); $l = [double[]]::new($n); $c = [double[]]::new($n); $v = [double[]]::new($n)
for ($i = 0; $i -lt $n; $i++) {
    $h[$i] = [double]$klines[$i].High; $l[$i] = [double]$klines[$i].Low
    $c[$i] = [double]$klines[$i].Close; $v[$i] = [double]$klines[$i].Volume
}
Write-Host "Arrays: $(Get-Date)"

$sig = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $c $h $l $v $n
Write-Host "Signal: $(Get-Date) len=$($sig.Length)"

# Trade indices
$tradeIdx = New-Object 'System.Collections.Generic.List[int]'
for ($si = 100; $si -lt $sig.Length; $si++) { if ($sig[$si]) { $tradeIdx.Add($si) } }
Write-Host "Trades: $(Get-Date) count=$($tradeIdx.Count)"

# Get returns
$retList = New-Object 'System.Collections.Generic.List[double]'
foreach ($idx in $tradeIdx) {
    $exitIdx = $idx + 5
    if ($exitIdx -ge $n) { continue }
    $retList.Add(($c[$exitIdx] - $c[$idx]) / $c[$idx] * 100)
}
Write-Host "Returns: $(Get-Date) count=$($retList.Count)"

$elapsed = [Math]::Round((Get-Date).Subtract($start).TotalMinutes, 2)
Write-Host "Done in $elapsed min"
