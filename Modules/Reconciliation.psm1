# Reconciliation.psm1 — State reconciliation (detection only, no auto-correct)

function Compare-ExchangeAndLocalPositions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ExchangePositions,
        [Parameter(Mandatory)]
        [array]$LocalPositions
    )
    $discrepancies = @()
    $exchangeMap = @{}
    foreach ($ep in $ExchangePositions) {
        $key = "$($ep.Symbol)|$($ep.Side)"
        $exchangeMap[$key] = $ep
    }
    $localMap = @{}
    foreach ($lp in $LocalPositions) {
        $key = "$($lp.Symbol)|$($lp.Side)"
        $localMap[$key] = $lp
    }
    $allKeys = ($exchangeMap.Keys + $localMap.Keys) | Sort-Object -Unique
    foreach ($key in $allKeys) {
        $onExchange = $exchangeMap.ContainsKey($key)
        $inLocal = $localMap.ContainsKey($key)
        if ($onExchange -and -not $inLocal) {
            $ep = $exchangeMap[$key]
            $discrepancies += [PSCustomObject]@{
                Type        = "POSITION_MISSING_LOCAL"
                Key         = $key
                Symbol      = $ep.Symbol
                Side        = $ep.Side
                ExchangeQty = $ep.Size
                LocalQty    = 0
                Detail      = "Position exists on exchange but not tracked locally"
            }
        } elseif (-not $onExchange -and $inLocal) {
            $lp = $localMap[$key]
            $discrepancies += [PSCustomObject]@{
                Type        = "POSITION_MISSING_EXCHANGE"
                Key         = $key
                Symbol      = $lp.Symbol
                Side        = $lp.Side
                ExchangeQty = 0
                LocalQty    = $lp.Size
                Detail      = "Position tracked locally but not found on exchange"
            }
        } elseif ($onExchange -and $inLocal) {
            $ep = $exchangeMap[$key]
            $lp = $localMap[$key]
            $qtyDiff = [Math]::Abs([double]$ep.Size - [double]$lp.Size)
            if ($qtyDiff -gt 1e-8) {
                $discrepancies += [PSCustomObject]@{
                    Type        = "POSITION_SIZE_MISMATCH"
                    Key         = $key
                    Symbol      = $ep.Symbol
                    Side        = $ep.Side
                    ExchangeQty = [double]$ep.Size
                    LocalQty    = [double]$lp.Size
                    Detail      = "Size differs by $qtyDiff"
                }
            }
        }
    }
    return $discrepancies
}

function Compare-ExchangeAndLocalOrders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ExchangeOrders,
        [Parameter(Mandatory)]
        [array]$LocalOrders
    )
    $discrepancies = @()
    $exchangeOrderIds = @{}
    foreach ($eo in $ExchangeOrders) {
        $exchangeOrderIds[$eo.OrderId] = $eo
    }
    $localOrderIds = @{}
    foreach ($lo in $LocalOrders) {
        $localOrderIds[$lo.OrderId] = $lo
    }
    $allIds = ($exchangeOrderIds.Keys + $localOrderIds.Keys) | Sort-Object -Unique
    foreach ($oid in $allIds) {
        $onExchange = $exchangeOrderIds.ContainsKey($oid)
        $inLocal = $localOrderIds.ContainsKey($oid)
        if ($onExchange -and -not $inLocal) {
            $eo = $exchangeOrderIds[$oid]
            $discrepancies += [PSCustomObject]@{
                Type       = "ORDER_MISSING_LOCAL"
                OrderId    = $oid
                Symbol     = $eo.Symbol
                ExchangeStatus = $eo.Status
                LocalStatus     = "N/A"
                Detail     = "Order exists on exchange but not tracked locally"
            }
        } elseif (-not $onExchange -and $inLocal) {
            $lo = $localOrderIds[$oid]
            $discrepancies += [PSCustomObject]@{
                Type       = "ORDER_MISSING_EXCHANGE"
                OrderId    = $oid
                Symbol     = $lo.Symbol
                ExchangeStatus = "N/A"
                LocalStatus     = $lo.Status
                Detail     = "Order tracked locally but not found on exchange"
            }
        }
    }
    return $discrepancies
}

function New-ReconciliationReport {
    [CmdletBinding()]
    param(
        [array]$PositionDiscrepancies,
        [array]$OrderDiscrepancies
    )
    return [PSCustomObject]@{
        Timestamp              = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        PositionDiscrepancies  = $PositionDiscrepancies
        OrderDiscrepancies     = $OrderDiscrepancies
        TotalDiscrepancies     = $PositionDiscrepancies.Count + $OrderDiscrepancies.Count
        IsConsistent           = ($PositionDiscrepancies.Count -eq 0 -and $OrderDiscrepancies.Count -eq 0)
    }
}

Export-ModuleMember -Function Compare-ExchangeAndLocalPositions, Compare-ExchangeAndLocalOrders, New-ReconciliationReport
