# PC Setup Script - Tyler Hatfield - v1.9
# Elevation check
$IsElevated = [System.Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544'
if (-not $IsElevated) {
    Write-Host "This script requires elevation. Please grant Administrator permissions." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Script setup
Clear-Host
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$logPathName = "PCSetupScriptLog.txt"
$logPath = Join-Path $DesktopPath $logPathName
$WUSPath = Join-Path -Path $PSScriptRoot -ChildPath 'Windows Update Script.ps1'
$functionPath = Join-Path -Path $PSScriptRoot -ChildPath 'Script Functions.ps1'
. "$functionPath"
$serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

# Set time zone and sync
Log-Message "Setting Time Zone to Eastern Standard Time..."
Set-TimeZone -Name "Eastern Standard Time" | Out-File -Append -FilePath $logPath
if ((Get-Service -Name w32time).Status -ne 'Running') {
    Start-Service -Name w32time | Out-File -Append -FilePath $logPath
}
w32tm /resync | Out-File -Append -FilePath $logPath

# Setup prerequisites and start Windows updates
Log-Message "Starting Windows Updates in the Background..."
Install-PackageProvider -Name NuGet -Force | Out-File -Append -FilePath $logPath
Install-Module -Name PSWindowsUpdate -Force | Out-File -Append -FilePath $logPath
Set-ExecutionPolicy Bypass -force | Out-File -Append -FilePath $logPath
Set-DODownloadMode -DownloadMode 3 | Out-File -Append -FilePath $logPath
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass", "-File `"$WUSPath`"" -WindowStyle Minimized

# Set/Create local admin account
Log-Message "Setup Local Admin Account(s)..."
$RepeatFunction = 1
While ($RepeatFunction -eq 1) {
	$AdminUser = Read-Host "Please enter the local admin Username"
	$AdminPass = Read-Host "Please enter the local admin Password"
	$UExists = Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue
	if (-not $UExists) {
		$MakeUser = Read-Host "The specified user does not exist, create account now? (y/N)"
		if ($MakeUser -eq "y" -or $MakeUser -eq "Y") {
			Net User $AdminUser $AdminPass /add | Out-File -Append -FilePath $logPath
		} else {
			Log-Message "Skipping account creation."
		}
	}
	$IsAdmin = (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^$AdminUser$" })
	if ($UExists -and -not $IsAdmin) {
		$MakeAdmin = Read-Host "The specified user is not a local admin, elevate now? (y/N)"
		if ($MakeAdmin -eq "y" -or $MakeAdmin -eq "Y") {
			Net Localgroup Administrators $AdminUser /add | Out-File -Append -FilePath $logPath
		} else {
			Log-Message "Skipping account elevation."
		}
	}
	$RFQ = Read-Host "Repeat this segment to add, edit or test another user account? (y/N)"
	if ($RFQ -ne "Y" -or $RFQ -ne "y") {
		$RepeatFunction = 0
	}
}

# Update WinGet and set defaults
Log-Message "Updating WinGet and App Installer..."
WinGet Source Update | Out-File -Append -FilePath $logPath
WinGet Upgrade --id Microsoft.Appinstaller --scope machine --accept-package-agreements --accept-source-agreements | Out-File -Append -FilePath $logPath
WinGet uninstall --id Microsoft.Teams.Free | Out-File -Append -FilePath $logPath
WinGet uninstall --id Microsoft.Teams | Out-File -Append -FilePath $logPath
winget uninstall "Teams Machine-Wide Installer" | Out-File -Append -FilePath $logPath
WinGet Upgrade --ALL --scope machine --accept-package-agreements --accept-source-agreements | Out-File -Append -FilePath $logPath

# Install programs based on selections, prepare Windows "Form"
Log-Message "Preparing Software List..."
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Program List'
$form.Size = New-Object System.Drawing.Size(400, 500)
$form.StartPosition = 'CenterScreen'

# Dynamic size based on number of programs
$checkboxHeight = 30    # Height of each checkbox
$progressBarHeight = 70 # Height of the progress bar
$buttonHeight = 80      # Height of the OK button
$padding = 20           # Padding around the elements

# Calculate total height based on the number of programs
$programs = @(
    @{ Name = 'Acrobat Reader'; WingetID = 'Adobe.Acrobat.Reader.64-bit' },
    @{ Name = 'Google Chrome'; WingetID = 'Google.Chrome' },
    @{ Name = 'MS Teams'; WingetID = 'Microsoft.Teams' },
    @{ Name = 'Firefox'; WingetID = 'Mozilla.Firefox' },
    @{ Name = '7-Zip'; WingetID = '7zip.7zip' },
    @{ Name = 'Google Drive'; WingetID = 'Google.Drive' },
    @{ Name = 'Dropbox'; WingetID = 'Dropbox.Dropbox' }
)

# Adjust form size based on the number of programs
$formHeight = ($programs.Count * $checkboxHeight) + $progressBarHeight + $buttonHeight + $padding
$form.Size = New-Object System.Drawing.Size(400, $formHeight)
$form.StartPosition = 'CenterScreen'

# Prepare Checkboxes
$checkboxes = @{ }
$y = 20
foreach ($program in $programs) {
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Location = New-Object System.Drawing.Point(20, $y)
    $checkbox.Text = $program.Name
    $form.Controls.Add($checkbox)
    $checkboxes[$program.Name] = $checkbox
    $y += $checkboxHeight
}

# Add progress bar to GUI
$progressBar = New-Object System.Windows.Forms.ProgressBar
$y += 10
$progressBar.Location = New-Object System.Drawing.Point(20, $y)
$progressBar.Size = New-Object System.Drawing.Size(340, 20)
$progressBar.Minimum = 0
$form.Controls.Add($progressBar)

# Add OK button
$okButton = New-Object System.Windows.Forms.Button
$y += 50
$okButton.Location = New-Object System.Drawing.Point(150, $y)
$okButton.Size = New-Object System.Drawing.Size(75, 30)
$okButton.Text = "OK"
$form.Controls.Add($okButton)

# Define a function to handle the OK button click
$okButton.Add_Click({
    # Disable OK button to prevent further clicks
    $okButton.Enabled = $false

    # Install selected programs
    $selectedPrograms = $checkboxes.GetEnumerator() | Where-Object { $_.Value.Checked } | ForEach-Object { $_.Key }
    $totalPrograms = $selectedPrograms.Count
    if ($totalPrograms -eq 0) {
        Log-Message "No programs selected for installation. Exiting." -ForegroundColor Yellow
        $form.Close()
        return
    }

    # Set progress bar maximum to match selected programs
    $progressBar.Maximum = $totalPrograms

    # Install programs and update progress bar
    $progressBar.Value = 0
    foreach ($programName in $selectedPrograms) {
        $program = $programs | Where-Object { $_.Name -eq $programName }
        if ($program -ne $null) {
            Log-Message "Installing $($program.Name)..."
            try {
                # Corrected WinGet command execution
                $wingetArgs = @(
                    "install",
                    "-e",  # Exact match flag
                    "--id", $program.WingetID,
                    "--scope", "machine",
                    "--accept-package-agreements",
                    "--accept-source-agreements"
                )

                # Use Start-Process with the correct arguments
                $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -PassThru -Wait

                # Capture the result
                if ($process.ExitCode -eq 0) {
                    $message = "$($program.Name): Installed successfully."
                    Log-Message $message -ForegroundColor Green
                } else {
                    $message = "$($program.Name): Installation failed with exit code $($process.ExitCode)."
                    Log-Message $message -ForegroundColor Red
                }
            } catch {
                $message = "$($program.Name): Installation failed. Error: $_"
                Log-Message $message -ForegroundColor Red
            }
        }
        $progressBar.Value += 1
        Start-Sleep -Milliseconds 200 # Simulate progress bar movement
    }

    # Close the form once installation is complete
    $form.Close()
})

# Show the GUI
$form.ShowDialog() | Out-null

# Rename PC and join to domain (if needed)
Log-Message "The PC is currently named: $env:computername"
$Rename = Read-Host "Would you like to change the PC name? y/n"
if ($Rename -eq "y" -or $Rename -eq "Y") {
    Log-Message "The serial number is: $serialNumber"
    $PCName = Read-Host "Enter the new PC name and press Enter"
    Rename-Computer -NewName $PCName -Force | Out-File -Append -FilePath $logPath
}
$Domain = Read-Host "Would you like to join this PC to an Active Directory Domain? y/n"
if ($Domain -eq "y" -or $Domain -eq "Y") {
    $DomainName = Read-Host "Enter the domain address and press Enter"
    $DomainUser = Read-Host "Enter the domain username and press Enter"
    Add-Computer -DomainName $DomainName -Credential $DomainUser | Out-File -Append -FilePath $logPath
}

# Reminders/Closing
Log-Message "Script setup is complete!"
Log-Message "Please install the agent and make any remaining changes needed."
Log-Message "Confirm Windows Updates have completed in the minimzied window and restart if needed."
Read-Host "Press enter to exit script"