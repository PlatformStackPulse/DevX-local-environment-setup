[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu-24.04",
    [switch]$InstallWingetApps,
    [switch]$InstallMobileTooling,
    [switch]$InstallTroubleshootingTooling,
    [string]$ConfigFile = "",
    [switch]$DryRun,
    [switch]$InstallVpnKit,
    [string]$VpnKitTarPath = "",
    [switch]$SkipFontInstall,
    [switch]$SkipRebootReminder
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session (Run as Administrator)."
    }
}

function Ensure-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Get-YamlValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Default = ""
    )

    if (-not (Test-Path $Path)) {
        return $Default
    }

    $result = $null
    $pattern = "^\s*$([Regex]::Escape($Key))\s*:\s*(.*?)\s*$"

    foreach ($line in Get-Content -Path $Path) {
        $clean = ($line -replace '#.*$', '').Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) {
            continue
        }
        if ($clean -match $pattern) {
            $value = $Matches[1].Trim().Trim('"').Trim("'")
            $result = $value
        }
    }

    if ([string]::IsNullOrWhiteSpace($result)) {
        return $Default
    }
    return $result
}

function Get-YamlBool {
    param(
        [string]$Path,
        [string]$Key,
        [bool]$Default = $false
    )

    $raw = (Get-YamlValue -Path $Path -Key $Key -Default "")
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Default
    }

    switch ($raw.ToLowerInvariant()) {
        "true" { return $true }
        "yes" { return $true }
        "1" { return $true }
        "false" { return $false }
        "no" { return $false }
        "0" { return $false }
        default { return $Default }
    }
}

function Ensure-WslConfig {
    $configPath = Join-Path $env:USERPROFILE ".wslconfig"
    $managedBlock = @"
# Managed by setup-windows-wsl.ps1
[wsl2]
networkingMode=mirrored
dnsTunneling=true
"@

    if (-not (Test-Path $configPath)) {
        Set-Content -Path $configPath -Value $managedBlock -Encoding UTF8
        Write-Host "Created $configPath"
        return
    }

    $existing = Get-Content -Path $configPath -Raw
    if ($existing -match "Managed by setup-windows-wsl.ps1") {
        Write-Host "WSL config already managed."
        return
    }

    $backup = "$configPath.bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
    Copy-Item -Path $configPath -Destination $backup -Force

    if ($existing -match '(?im)^\s*\[wsl2\]') {
        Write-Warning "An existing [wsl2] section was found in $configPath. Appending the managed block may create a duplicate [wsl2] section with unclear precedence. Review and merge the keys manually. Backup saved to $backup."
    }

    Add-Content -Path $configPath -Value "`n$managedBlock"
    Write-Host "Backed up existing config to $backup and appended managed settings."
}

function Install-MesloFonts {
    $fontDir = Join-Path $env:TEMP "meslo-fonts"
    $targetDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    $fonts = @(
        @{ Name = "MesloLGS NF Regular.ttf"; Url = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"; Reg = "MesloLGS NF Regular (TrueType)" },
        @{ Name = "MesloLGS NF Bold.ttf"; Url = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"; Reg = "MesloLGS NF Bold (TrueType)" },
        @{ Name = "MesloLGS NF Italic.ttf"; Url = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"; Reg = "MesloLGS NF Italic (TrueType)" },
        @{ Name = "MesloLGS NF Bold Italic.ttf"; Url = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"; Reg = "MesloLGS NF Bold Italic (TrueType)" }
    )

    foreach ($font in $fonts) {
        $downloadPath = Join-Path $fontDir $font.Name
        $installedPath = Join-Path $targetDir $font.Name
        Invoke-WebRequest -Uri $font.Url -OutFile $downloadPath
        Copy-Item -Path $downloadPath -Destination $installedPath -Force
        New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -Name $font.Reg -Value $font.Name -PropertyType String -Force | Out-Null
        Write-Host "Installed font: $($font.Name)"
    }
}

function Ensure-WingetApp {
    param(
        [string]$Id,
        [string]$Display
    )

    try {
        winget list --id $Id --exact | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$Display is already installed."
            return
        }
    } catch {
        # Keep going to install attempt.
    }

    winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install $Display ($Id) via winget. Continuing."
    }
}

function Add-UserPathEntry {
    param([string]$Entry)

    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrWhiteSpace($current)) {
        [Environment]::SetEnvironmentVariable("Path", $Entry, "User")
        return
    }

    $parts = $current.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    if ($parts -contains $Entry) {
        return
    }

    $updated = ($parts + $Entry) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $updated, "User")
}

function Configure-AndroidEnvironment {
    $androidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    [Environment]::SetEnvironmentVariable("ANDROID_HOME", $androidSdk, "User")
    [Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $androidSdk, "User")

    Add-UserPathEntry -Entry (Join-Path $androidSdk "platform-tools")
    Add-UserPathEntry -Entry (Join-Path $androidSdk "cmdline-tools\latest\bin")

    Write-Host "Configured user environment variables: ANDROID_HOME, ANDROID_SDK_ROOT"
}

function Format-Bool {
    param([bool]$Value)
    if ($Value) {
        return "enabled"
    }
    return "disabled"
}

function Show-DryRunPlan {
    param(
        [string]$Distro,
        [bool]$InstallWingetApps,
        [bool]$InstallMobileTooling,
        [bool]$InstallTroubleshootingTooling,
        [bool]$InstallVpnKit,
        [string]$VpnKitTarPath,
        [bool]$SkipFontInstall,
        [bool]$SkipRebootReminder,
        [string]$ConfigFile
    )

    Write-Step "Dry-run mode is enabled"
    Write-Host "No changes will be applied."
    Write-Host "Config file: $ConfigFile"
    Write-Host ""
    Write-Host "Planned actions from feature flags:"
    Write-Host "- target distro: $Distro"
    Write-Host "- enable WSL features + set WSL2 default: enabled"
    Write-Host "- apply managed .wslconfig: enabled"
    Write-Host "- install Meslo Nerd Fonts: $(Format-Bool (-not $SkipFontInstall))"
    Write-Host "- install common winget apps: $(Format-Bool $InstallWingetApps)"
    Write-Host "- install troubleshooting + cloud tooling: $(Format-Bool $InstallTroubleshootingTooling)"
    Write-Host "- install mobile tooling (Android Studio + Flutter): $(Format-Bool $InstallMobileTooling)"
    Write-Host "- import wsl-vpnkit distro: $(Format-Bool $InstallVpnKit)"
    if ($InstallVpnKit) {
        Write-Host "- vpnkit_tar_path: $VpnKitTarPath"
    }
    Write-Host "- reboot reminder: $(Format-Bool (-not $SkipRebootReminder))"
}

Write-Step "Checking prerequisites"
Ensure-Command -Name "wsl"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigFile = Join-Path $scriptDir "setup-windows-wsl.yaml"
}

if (Test-Path $ConfigFile) {
    Write-Step "Loading feature flags from $ConfigFile"

    if (-not $PSBoundParameters.ContainsKey('Distro')) {
        $Distro = Get-YamlValue -Path $ConfigFile -Key "distro" -Default $Distro
    }
    if (-not $PSBoundParameters.ContainsKey('InstallWingetApps')) {
        $InstallWingetApps = (Get-YamlBool -Path $ConfigFile -Key "install_winget_apps" -Default $false)
    }
    if (-not $PSBoundParameters.ContainsKey('InstallMobileTooling')) {
        $InstallMobileTooling = (Get-YamlBool -Path $ConfigFile -Key "install_mobile_tooling" -Default $false)
    }
    if (-not $PSBoundParameters.ContainsKey('InstallTroubleshootingTooling')) {
        $InstallTroubleshootingTooling = (Get-YamlBool -Path $ConfigFile -Key "install_troubleshooting_tooling" -Default $false)
    }
    if (-not $PSBoundParameters.ContainsKey('InstallVpnKit')) {
        $InstallVpnKit = (Get-YamlBool -Path $ConfigFile -Key "install_vpnkit" -Default $false)
    }
    if (-not $PSBoundParameters.ContainsKey('VpnKitTarPath')) {
        $VpnKitTarPath = Get-YamlValue -Path $ConfigFile -Key "vpnkit_tar_path" -Default $VpnKitTarPath
    }
    if (-not $PSBoundParameters.ContainsKey('SkipFontInstall')) {
        $SkipFontInstall = (Get-YamlBool -Path $ConfigFile -Key "skip_font_install" -Default $false)
    }
    if (-not $PSBoundParameters.ContainsKey('SkipRebootReminder')) {
        $SkipRebootReminder = (Get-YamlBool -Path $ConfigFile -Key "skip_reboot_reminder" -Default $false)
    }
}

$DryRunEnabled = $DryRun.IsPresent
if (-not $PSBoundParameters.ContainsKey('DryRun')) {
    $DryRunEnabled = (Get-YamlBool -Path $ConfigFile -Key "dry_run" -Default $false)
}

if ($DryRunEnabled) {
    Show-DryRunPlan -Distro $Distro `
        -InstallWingetApps $InstallWingetApps `
        -InstallMobileTooling $InstallMobileTooling `
        -InstallTroubleshootingTooling $InstallTroubleshootingTooling `
        -InstallVpnKit $InstallVpnKit `
        -VpnKitTarPath $VpnKitTarPath `
        -SkipFontInstall $SkipFontInstall `
        -SkipRebootReminder $SkipRebootReminder `
        -ConfigFile $ConfigFile
    return
}

Assert-Admin

Write-Step "Enabling WSL and virtual machine features"
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart | Out-Null
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart | Out-Null

Write-Step "Updating WSL and setting WSL2 default"
wsl --update
wsl --set-default-version 2

Write-Step "Installing distro '$Distro' if needed"
$installedDistros = (wsl --list --quiet) | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
if ($installedDistros -contains $Distro) {
    Write-Host "$Distro already installed."
} else {
    wsl --install -d $Distro
}

Write-Step "Applying .wslconfig networking defaults"
Ensure-WslConfig

if (-not $SkipFontInstall) {
    Write-Step "Installing Meslo Nerd Fonts for terminal rendering"
    Install-MesloFonts
} else {
    Write-Host "Skipping font install as requested."
}

if ($InstallWingetApps) {
    Write-Step "Installing common Windows tools via winget"
    Ensure-Command -Name "winget"
    Ensure-WingetApp -Id "Git.Git" -Display "Git"
    Ensure-WingetApp -Id "Microsoft.VisualStudioCode" -Display "Visual Studio Code"
    Ensure-WingetApp -Id "Docker.DockerDesktop" -Display "Docker Desktop"
    Ensure-WingetApp -Id "Microsoft.WindowsTerminal" -Display "Windows Terminal"
}

if ($InstallTroubleshootingTooling) {
    Write-Step "Installing troubleshooting and cloud CLIs on Windows host (best effort)"
    Ensure-Command -Name "winget"

    # Cloud CLIs on host are useful for non-WSL troubleshooting and admin tasks.
    Ensure-WingetApp -Id "Amazon.AWSCLI" -Display "AWS CLI"
    Ensure-WingetApp -Id "Microsoft.AzureCLI" -Display "Azure CLI"
    Ensure-WingetApp -Id "Google.CloudSDK" -Display "Google Cloud SDK"

    # Troubleshooting toolkit.
    Ensure-WingetApp -Id "BurntSushi.ripgrep.MSVC" -Display "ripgrep"
    Ensure-WingetApp -Id "jqlang.jq" -Display "jq"
    Ensure-WingetApp -Id "Nmap.Nmap" -Display "Nmap"
    Ensure-WingetApp -Id "WiresharkFoundation.Wireshark" -Display "Wireshark"
}

if ($InstallMobileTooling) {
    Write-Step "Installing Windows mobile tooling (Flutter + Android Studio)"
    Ensure-Command -Name "winget"

    Ensure-WingetApp -Id "Google.AndroidStudio" -Display "Android Studio"
    Ensure-WingetApp -Id "Flutter.Flutter" -Display "Flutter SDK"

    Configure-AndroidEnvironment

    Write-Host "Open Android Studio once to finish SDK component install and emulator setup."
    Write-Host "After opening a new terminal, run: flutter doctor"
}

if ($InstallVpnKit) {
    Write-Step "Importing wsl-vpnkit distro"
    if (-not $VpnKitTarPath) {
        throw "You passed -InstallVpnKit but did not provide -VpnKitTarPath."
    }
    if (-not (Test-Path $VpnKitTarPath)) {
        throw "VpnKitTarPath does not exist: $VpnKitTarPath"
    }

    $target = Join-Path $env:USERPROFILE "wsl-vpnkit"
    if (-not (Test-Path $target)) {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
    }

    $hasVpnKit = $false
    foreach ($d in $installedDistros) {
        if ($d -eq "wsl-vpnkit") {
            $hasVpnKit = $true
            break
        }
    }

    if ($hasVpnKit) {
        Write-Host "wsl-vpnkit already imported."
    } else {
        wsl --import wsl-vpnkit $target $VpnKitTarPath --version 2
        Write-Host "Imported wsl-vpnkit successfully."
    }
}

Write-Step "Shutting down WSL to apply changes"
wsl --shutdown

if (-not $SkipRebootReminder) {
    Write-Host "`nA Windows restart is recommended before continuing." -ForegroundColor Yellow
}

Write-Host "`nNext step:" -ForegroundColor Green
Write-Host "1) Launch Ubuntu in WSL."
Write-Host "2) Run: bash ~/setup-ubuntu-wsl.sh  (after copying the bash script into WSL)"
