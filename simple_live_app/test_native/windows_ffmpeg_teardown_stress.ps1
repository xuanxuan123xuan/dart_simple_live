param(
    [Parameter(Mandatory = $true)]
    [string] $Executable,

    [Parameter(Mandatory = $true)]
    [string] $OutputRoot,

    [ValidateRange(1, 1000)]
    [int] $Iterations = 30
)

$ErrorActionPreference = 'Stop'

$exePath = (Resolve-Path -LiteralPath $Executable).Path
$outputRootPath = [System.IO.Path]::GetFullPath($OutputRoot)
[System.IO.Directory]::CreateDirectory($outputRootPath) | Out-Null

$runName = 'ffmpeg-teardown-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $PID
$runRoot = Join-Path $outputRootPath $runName
[System.IO.Directory]::CreateDirectory($runRoot) | Out-Null

$runTimeoutSeconds = 20
$startMarkerTimeoutSeconds = 12
$applicationErrorProvider = 'Application Error'
$applicationErrorStart = (Get-Date).AddDays(-30)
$results = [System.Collections.Generic.List[object]]::new()

function Get-SimpleLiveApplicationErrors {
    param(
        [Parameter(Mandatory = $true)]
        [datetime] $StartTime,

        [Parameter(Mandatory = $true)]
        [datetime] $EndTime,

        [Parameter(Mandatory = $true)]
        [int] $Limit
    )

    $eventMatches = [System.Collections.Generic.List[object]]::new()
    $queryError = $null
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName      = 'Application'
            ProviderName = $applicationErrorProvider
            Id           = 1000
            StartTime    = $StartTime
            EndTime      = $EndTime
        } -ErrorAction Stop

        foreach ($event in $events) {
            $message = [string] $event.Message
            if ($message -match '(?i)simple_live_app(?:\.exe)?') {
                $eventMatches.Add([pscustomobject]@{
                    eventId       = $event.Id
                    recordId      = $event.RecordId
                    timeCreatedUtc = $event.TimeCreated.ToUniversalTime().ToString('o')
                    provider      = $event.ProviderName
                    message       = $message
                })
                if ($eventMatches.Count -ge $Limit) { break }
            }
        }
    }
    catch {
        if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound') {
            $queryError = $_.Exception.Message
        }
    }

    return [pscustomobject]@{
        events = @($eventMatches.ToArray())
        error  = $queryError
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [object] $Value
    )

    $json = ConvertTo-Json -InputObject $Value -Depth 10
    [System.IO.File]::WriteAllText(
        $Path,
        $json,
        [System.Text.UTF8Encoding]::new($false)
    )
}

foreach ($mode in @('active-close', 'cancel-close')) {
    for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
        $runId = '{0}-{1:D3}' -f $mode, $iteration
        $iterationRoot = Join-Path $runRoot $runId
        [System.IO.Directory]::CreateDirectory($iterationRoot) | Out-Null

        $startedMarker = Join-Path $iterationRoot 'started.json'
        $failureMarker = Join-Path $iterationRoot 'failure.json'
        $preEventTime = Get-Date
        $preEvents = Get-SimpleLiveApplicationErrors `
            -StartTime $applicationErrorStart `
            -EndTime $preEventTime `
            -Limit 20

        $launchedAt = Get-Date
        $process = $null
        $timedOut = $false
        $launchError = $null
        $exitCode = $null
        $exitCodeHex = $null
        $markerSeen = $false

        try {
            $quotedOutputDirectory = '"{0}"' -f $iterationRoot
            $argumentLine = '--mode={0} --output-dir={1}' -f $mode, $quotedOutputDirectory
            $process = Start-Process `
                -FilePath $exePath `
                -ArgumentList $argumentLine `
                -WorkingDirectory (Split-Path -Parent $exePath) `
                -WindowStyle Hidden `
                -PassThru

            $markerDeadline = (Get-Date).AddSeconds($startMarkerTimeoutSeconds)
            while ((Get-Date) -lt $markerDeadline) {
                if (Test-Path -LiteralPath $startedMarker) {
                    $markerSeen = $true
                    break
                }
                if (Test-Path -LiteralPath $failureMarker) { break }
                $process.Refresh()
                if ($process.HasExited) { break }
                Start-Sleep -Milliseconds 100
            }

            if (-not $process.HasExited) {
                $process.Refresh()
                if (-not $process.WaitForExit($runTimeoutSeconds * 1000)) {
                    $timedOut = $true
                    # This process object is the PID started by this iteration.
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    $process.WaitForExit(5000) | Out-Null
                }
            }

            $process.Refresh()
            if ($process.HasExited) {
                $exitCode = $process.ExitCode
                $exitCodeHex = '0x{0:X8}' -f ([uint32] ([int64] $exitCode -band 0xffffffffL))
            }
        }
        catch {
            $launchError = $_.Exception.Message
            if ($process -and -not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
        }

        # Give Windows Event Log a short moment to publish a crash record.
        Start-Sleep -Milliseconds 300
        $endedAt = Get-Date
        $postEvents = Get-SimpleLiveApplicationErrors `
            -StartTime $launchedAt.AddSeconds(-2) `
            -EndTime $endedAt.AddSeconds(1) `
            -Limit 50

        $startData = $null
        if (Test-Path -LiteralPath $startedMarker) {
            try {
                $startData = Get-Content -LiteralPath $startedMarker -Raw | ConvertFrom-Json
                $markerSeen = $true
            }
            catch {
                $startData = @{ parseError = $_.Exception.Message }
            }
        }

        $failureData = $null
        if (Test-Path -LiteralPath $failureMarker) {
            try {
                $failureData = Get-Content -LiteralPath $failureMarker -Raw | ConvertFrom-Json
            }
            catch {
                $failureData = @{ parseError = $_.Exception.Message }
            }
        }

        $eventLogReadable = ($null -eq $preEvents.error -and $null -eq $postEvents.error)
        $passed = ($markerSeen -and -not $timedOut -and -not $launchError -and
            $exitCode -eq 0 -and $postEvents.events.Count -eq 0 -and
            $eventLogReadable -and $null -eq $failureData)
        $results.Add([pscustomobject]@{
            runId          = $runId
            mode           = $mode
            iteration      = $iteration
            passed         = $passed
            pid            = if ($process) { $process.Id } else { $null }
            markerSeen     = $markerSeen
            applicationErrorLogReadable = $eventLogReadable
            started        = $startData
            failure        = $failureData
            timedOut       = $timedOut
            launchError    = $launchError
            exitCode       = $exitCode
            exitCodeHex    = $exitCodeHex
            startedAtUtc   = $launchedAt.ToUniversalTime().ToString('o')
            endedAtUtc     = $endedAt.ToUniversalTime().ToString('o')
            appErrorsBefore = $preEvents
            appErrorsAfter  = $postEvents
        })

        Write-Output ('{0}: {1} (exit={2}, appErrors={3})' -f `
            $runId, $(if ($passed) { 'PASS' } else { 'FAIL' }), $exitCodeHex, $postEvents.events.Count)
    }
}

$resultFile = Join-Path $runRoot 'result.json'
$document = [pscustomobject]@{
    executable         = $exePath
    outputRoot         = $runRoot
    iterationsPerMode  = $Iterations
    totalRuns          = $results.Count
    passedRuns         = @($results | Where-Object passed).Count
    failedRuns         = @($results | Where-Object { -not $_.passed }).Count
    createdAtUtc       = [datetime]::UtcNow.ToString('o')
    runs               = @($results.ToArray())
}
Write-JsonFile -Path $resultFile -Value $document

Write-Output "Results: $resultFile"
if ($document.failedRuns -gt 0) {
    exit 1
}
