# Windows Update PS Script Module - Tyler Hatfield - v1.4

# Window and script setup
try {
	$dWidth = (Get-Host).UI.RawUI.BufferSize.Width
	$dHeight = 40
	$rawUI = $Host.UI.RawUI
	$newSize = New-Object System.Management.Automation.Host.Size ($dWidth, $dHeight)
	$rawUI.WindowSize = $newSize
} catch {
	$failedResizeU = 1
}
try {
	$host.UI.RawUI.BackgroundColor = "Black"
} catch {
	$failedColorU = 1
}
Clear-Host
if ($failedResizeU -eq 1 -or $failedColorU -eq 1) {Write-Host "Failed to resize window and/or set background color." -ForegroundColor "Red"}

# Define noUpdates Function
function noUpdatesEnd {
	Read-Host "Press enter to exit the script" 
	exit
}

# Import the PSWindowsUpdate module
try {
    Import-Module PSWindowsUpdate
} catch {
    Write-Host "The PSWindowsUpdate module failed to import. Please ensure NuGet operations completed successfully in the main script before retrying." -ForegroundColor "Red"
}

# Function to display progress
function Show-ProgressBar {
    param(
        [string]$status,
        [int]$percent
    )
    
    Write-Progress -PercentComplete $percent -Activity "$status" -Status "$status" -CurrentOperation "Please wait..."
}

# Step 1: Get all available updates
$updates = Get-WindowsUpdate | Where-Object { 
    $title = $_.Title
}

$filterWU = Read-Host "Apply Cumulative updates? (y/N)" -ForegroundColor "Yellow"
# Filters out updates based on key phrases in $excludeUpdates
if (-not ($filterWU.ToLower() -eq "yes" -or $filterWU.ToLower() -eq "y")) {
    $excludeUpdates = @("Cumulative Update for Windows", "Feature", "Upgrade")
    $filteredUpdates = $title | Where-Object { 
    	$currentupdate = $_
    	$containsexs = $false
    	foreach ($word in $excludeUpdates) {
    		if ($currentupdate -like "*$word*") {
    			$containsexs = $true
    			break
    		}
    	}
    	-not $containsexs
    }
    $updates = $filteredUpdates
}


Write-Host "Updates to be installed:"
$updates | ForEach-Object { Write-Host $_.Title }

# Check if there are any updates to install
if (-not $updates -or $updates.Count -eq 0) {
    Write-Host "No updates available."
    noUpdatesEnd
}

# Step 2: Show progress for downloading updates
$totalUpdates = $updates.Count
$counter = 0

foreach ($update in $updates) {
    $counter++
    Show-ProgressBar -status "Downloading updates..." -percent (($counter / $totalUpdates) * 100)
}

# Step 3: Proceed with installing updates
Write-Host "`nDownloading and installing updates..."

$counter = 0
foreach ($update in $updates) {
	$counter++
	Show-ProgressBar -status "Installing updates..." -percent (($counter / $totalUpdates) * 100)
	# Install each update (no re-scan after installation)
	Install-WindowsUpdate -UpdateID $update.UpdateID -AcceptAll -IgnoreReboot -Verbose
}

# Check if a reboot is required after installation
$rebootRequired = (Get-WindowsUpdate -IsPending).Count -gt 0

if ($rebootRequired) {
    Write-Host "`nA reboot is required to complete the installation of updates." -ForegroundColor "Yellow"
    # Optional: Uncomment the following line to automatically restart the system.
    # Restart-Computer -Force
}

Write-Host "`nUpdate process completed. Press Enter to exit:" -ForegroundColor "Green"
Read-Host