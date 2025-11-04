# Clear the console screen
Clear-Host

# Script header
Write-Host "USN Journal Tampering Check" -ForegroundColor Magenta
Write-Host "=============================" -ForegroundColor Magenta
Write-Output ""

# Function to check if a log exists
function LogExists($logName) {
    try {
        Get-WinEvent -ListLog $logName -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Check Application log for Event ID 3079 (AppLocker/WDAC blocks or VM prep)
$appUSN = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=3079} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, @{n='Message';e={$_.Message -replace "`r`n"," "}}

# Check DFS Replication log if it exists
$dfsUSN = $null
if (LogExists 'DFS Replication') {
    $dfsUSN = Get-WinEvent -FilterHashtable @{LogName='DFS Replication'; Id=2204,2213} -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, @{n='Message';e={$_.Message -replace "`r`n"," "}}
}

# Check File Replication Service log if it exists
$frsUSN = $null
if (LogExists 'File Replication Service') {
    $frsUSN = Get-WinEvent -FilterHashtable @{LogName='File Replication Service'; Id=13568} -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, @{n='Message';e={$_.Message -replace "`r`n"," "}}
}

# Check Security log for Event ID 4688 (process execution, e.g., fsutil usn deletejournal) if auditing enabled
$secUSN = $null
if (LogExists 'Security') {
    $secUSN = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4688} -ErrorAction SilentlyContinue |
        Where-Object { 
            $_.Message -match 'fsutil.*usn.*deletejournal' -or
            $_.Message -match 'wevtutil.*cl' -or
            $_.Message -match 'Clear-EventLog'
        } |
        Select-Object TimeCreated, Id, @{n='Message';e={$_.Message -replace "`r`n"," "}}
}

# Check System log for Event ID 104 (Event Log cleared)
$sysClear = $null
if (LogExists 'System') {
    $sysClear = Get-WinEvent -FilterHashtable @{LogName='System'; Id=104} -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, @{n='Message'; e={$_.Message -replace "`r`n"," "}}
}

# Combine and display all events
$allEvents = @($appUSN + $dfsUSN + $frsUSN + $secUSN + $sysClear) | Where-Object { $_ } | Sort-Object TimeCreated
Write-Output ""
if ($allEvents) {
    Write-Host "Relevant Events Found:" -ForegroundColor Green
    $allEvents | Format-Table -AutoSize -Property TimeCreated, Id, Message | Out-String | Write-Host -ForegroundColor Green
} else {
    Write-Host "No relevant events found." -ForegroundColor Red
}
Write-Output ""

# Check USN Journal state for C: drive
Write-Host "Checking USN Journal state for C: drive:" -ForegroundColor Cyan
try {
    $journal = fsutil usn queryjournal C:
    Write-Host ($journal | Out-String) -ForegroundColor Yellow
} catch {
    Write-Host "Error querying USN journal for C: drive. Ensure drive exists and you have admin privileges." -ForegroundColor Red
}
Write-Output ""

# --- Journal Recreation Detection ---
Write-Host "Checking if Journal ID has changed since last run..." -ForegroundColor Cyan

$journalInfo = fsutil usn queryjournal C: 2>$null
if ($journalInfo) {
    # Extract the Journal ID
    $currentID = ($journalInfo | Select-String "Journal ID").ToString().Split(":")[1].Trim()
    $savePath = "$env:ProgramData\USN_Journal_ID.txt"

    if (Test-Path $savePath) {
        $previousID = Get-Content $savePath
        if ($previousID -ne $currentID) {
            Write-Host "⚠️  Journal ID has changed! The USN Journal may have been deleted or recreated." -ForegroundColor Red
            Write-Host "Previous ID: $previousID" -ForegroundColor Yellow
            Write-Host "Current ID:  $currentID" -ForegroundColor Yellow
        } else {
            Write-Host "✅ Journal ID matches previous run (no recreation detected)." -ForegroundColor Green
        }
    } else {
        Write-Host "No previous Journal ID found — saving current ID for future comparison." -ForegroundColor Yellow
    }

    # Save the current ID for future comparison
    $currentID | Out-File -FilePath $savePath -Force -Encoding ascii
} else {
    Write-Host "Unable to read Journal ID (fsutil may have failed or requires admin privileges)." -ForegroundColor Red
}
Write-Output ""

# Get Creation Time for the USN Journal ($J)
Write-Host "Retrieving Creation Time for the USN Journal ($J)..." -ForegroundColor Cyan
try {
    $journalPath = "C:\$Extend\$UsnJrnl"
    $journalFile = Get-Item -Path $journalPath -Force -ErrorAction SilentlyContinue
    if ($journalFile) {
        Write-Host "USN Journal Creation Time:" -ForegroundColor Yellow
        $journalFile | Select-Object Name, CreationTime | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor Yellow
    } else {
        Write-Host "Could not access USN Journal file. Ensure you have admin privileges and the path is correct." -ForegroundColor Red
    }
} catch {
    Write-Host "Error retrieving USN Journal Creation Time." -ForegroundColor Red
}
Write-Output ""
