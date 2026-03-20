<#
.SYNOPSIS
    Veeam Job State Manager - Sichert und restauriert Job-Zustaende bei Veeam Updates.

.DESCRIPTION
    GUI-Tool fuer den Einsatz auf Veeam Backup & Replication Servern waehrend Updates/Upgrades.

    Workflow:
    1. SAVE     - Dokumentiert den Enabled/Disabled-Zustand aller Backup-Jobs als JSON
    2. DISABLE  - Deaktiviert alle Jobs, wartet auf laufende Jobs, deaktiviert diese nach Abschluss
    3. (Veeam Update durchfuehren)
    4. RESTORE  - Stellt den urspruenglichen Zustand exakt wieder her

    Unterstuetzte Job-Typen:
    - VBRJob (VMware/Hyper-V Backup, Replication, File Copy)
    - VBRTapeJob (Backup to Tape, File to Tape)
    - VBRSureBackupJob / VSBJob (SureBackup)
    - VBRBackupCopyJob (Backup Copy, ab v12 separat)
    - VBRComputerBackupJob (Agent Backup)
    - VBRComputerBackupCopyJob (Agent Backup Copy)
    - VBRUnstructuredBackupJob / VBRNASBackupJob (NAS/File Share Backup)
    - VBRCDPPolicy (Continuous Data Protection)
    - VBRPluginJob (Enterprise App Backup: Oracle RMAN, SAP HANA etc.)

    Kompatibel mit Veeam v9, v10, v11, v12 (Snap-in und Modul)

.NOTES
    Version: 1.2.0
    Autor:   Lars Bahlmann
    Firma:   badata GmbH - www.badata.de
    Web:     https://www.badata.de
    GitHub:  https://github.com/badata/VeeamJobStateManager
    Lizenz:  MIT
    Datei:   VeeamJobManager_v1.2.0.ps1
#>

$script:AppVersion = "1.2.0"

# --- Umlaute sicher kodiert (unabhaengig von Datei-Encoding) ---
$ae = [string][char]0xE4  # ae
$oe = [string][char]0xF6  # oe
$ue = [string][char]0xFC  # ue
$sz = [string][char]0xDF  # ss

# --- WPF laden ---
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- Konfiguration ---
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
try {
    $script:FQDN = ([System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)).HostName
}
catch {
    $script:FQDN = $env:COMPUTERNAME
}

# --- Log-Datei ---
$script:LogFile = Join-Path $ScriptDir "VeeamJobManager_$($script:FQDN).log"

# --- XAML GUI Definition ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Veeam Job State Manager"
        Width="900" Height="700"
        MinWidth="750" MinHeight="550"
        WindowStartupLocation="CenterScreen"
        Background="#1E1E2E">
    <Window.Resources>
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Height" Value="60"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                CornerRadius="6" Padding="16,8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DarkComboBox" TargetType="ComboBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="Black"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="Height" Value="30"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="8,4"/>
        </Style>
        <Style x:Key="DarkComboBoxItem" TargetType="ComboBoxItem">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="Black"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Style.Triggers>
                <Trigger Property="IsHighlighted" Value="True">
                    <Setter Property="Background" Value="#89B4FA"/>
                    <Setter Property="Foreground" Value="Black"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#89B4FA"/>
                    <Setter Property="Foreground" Value="Black"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="180"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="0,0,0,16">
            <TextBlock Text="Veeam Job State Manager"
                       FontSize="24" FontWeight="Bold" Foreground="#CDD6F4"/>
            <TextBlock Text="Job-Zust&#xE4;nde sichern, deaktivieren und wiederherstellen"
                       FontSize="12" Foreground="#6C7086" Margin="0,4,0,0"/>
        </StackPanel>

        <!-- Status Banner -->
        <Border x:Name="pnlStatusBanner" Grid.Row="1" Background="#F9E2AF" CornerRadius="6"
                Padding="16,10" Margin="0,0,0,12" Visibility="Collapsed">
            <TextBlock x:Name="txtStatusBanner" Text="" FontSize="15" FontWeight="Bold"
                       HorizontalAlignment="Center" Foreground="#1E1E2E"/>
        </Border>

        <!-- Buttons -->
        <Grid Grid.Row="2" Margin="0,0,0,16">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Button x:Name="btnSave" Grid.Column="0" Style="{StaticResource ActionButton}"
                    Background="#45475A">
                <StackPanel>
                    <TextBlock Text="SAVE" FontSize="16" FontWeight="Bold"
                               HorizontalAlignment="Center" Foreground="#89B4FA"/>
                    <TextBlock Text="Zustand dokumentieren" FontSize="11"
                               HorizontalAlignment="Center" Foreground="#A6ADC8"/>
                </StackPanel>
            </Button>

            <Button x:Name="btnDisable" Grid.Column="2" Style="{StaticResource ActionButton}"
                    Background="#45475A">
                <StackPanel>
                    <TextBlock Text="DISABLE ALL" FontSize="16" FontWeight="Bold"
                               HorizontalAlignment="Center" Foreground="#F9E2AF"/>
                    <TextBlock Text="Alle Jobs deaktivieren" FontSize="11"
                               HorizontalAlignment="Center" Foreground="#A6ADC8"/>
                </StackPanel>
            </Button>

            <Button x:Name="btnRestore" Grid.Column="4" Style="{StaticResource ActionButton}"
                    Background="#45475A">
                <StackPanel>
                    <TextBlock Text="RESTORE" FontSize="16" FontWeight="Bold"
                               HorizontalAlignment="Center" Foreground="#A6E3A1"/>
                    <TextBlock Text="Zustand wieder herstellen" FontSize="11"
                               HorizontalAlignment="Center" Foreground="#A6ADC8"/>
                </StackPanel>
            </Button>
        </Grid>

        <!-- State File Auswahl -->
        <Grid Grid.Row="3" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Zustandsdatei:" Foreground="#A6ADC8"
                       VerticalAlignment="Center" Margin="0,0,8,0" FontSize="12"/>
            <ComboBox x:Name="cmbStateFiles" Grid.Column="1"
                      Style="{StaticResource DarkComboBox}"
                      ItemContainerStyle="{StaticResource DarkComboBoxItem}"/>
            <Button x:Name="btnRefreshFiles" Grid.Column="2" Content="Aktualisieren" Width="Auto" Height="30"
                    Background="#45475A" Foreground="#CDD6F4" BorderThickness="0" Cursor="Hand"
                    Margin="8,0,0,0" FontSize="14"/>
        </Grid>

        <!-- Job-Tabelle -->
        <DataGrid x:Name="dgJobs" Grid.Row="4" Margin="0,0,0,12"
                  AutoGenerateColumns="False" IsReadOnly="True"
                  Background="#313244" Foreground="#CDD6F4"
                  BorderBrush="#45475A" BorderThickness="1"
                  RowBackground="#313244" AlternatingRowBackground="#3B3D50"
                  GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#45475A"
                  HeadersVisibility="Column" CanUserReorderColumns="False"
                  SelectionMode="Single" FontSize="12">
            <DataGrid.ColumnHeaderStyle>
                <Style TargetType="DataGridColumnHeader">
                    <Setter Property="Background" Value="#45475A"/>
                    <Setter Property="Foreground" Value="#CDD6F4"/>
                    <Setter Property="Padding" Value="8,6"/>
                    <Setter Property="FontWeight" Value="SemiBold"/>
                    <Setter Property="BorderBrush" Value="#585B70"/>
                    <Setter Property="BorderThickness" Value="0,0,1,1"/>
                </Style>
            </DataGrid.ColumnHeaderStyle>
            <DataGrid.Columns>
                <DataGridTextColumn Header="Job Name" Binding="{Binding Name}" Width="*"/>
                <DataGridTextColumn Header="Typ" Binding="{Binding Type}" Width="150"/>
                <DataGridTextColumn Header="Status" Binding="{Binding StatusText}" Width="100"/>
            </DataGrid.Columns>
        </DataGrid>

        <!-- Status Bar -->
        <Grid Grid.Row="5" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="#A6E3A1" CornerRadius="3" Padding="8,3" Margin="0,0,8,0">
                <TextBlock x:Name="txtEnabledCount" Text="Aktiv: 0" FontSize="12"
                           FontWeight="SemiBold" Foreground="#1E1E2E"/>
            </Border>
            <Border Grid.Column="1" Background="#F38BA8" CornerRadius="3" Padding="8,3" Margin="0,0,8,0">
                <TextBlock x:Name="txtDisabledCount" Text="Inaktiv: 0" FontSize="12"
                           FontWeight="SemiBold" Foreground="#1E1E2E"/>
            </Border>
            <Border Grid.Column="2" Background="#89B4FA" CornerRadius="3" Padding="8,3">
                <TextBlock x:Name="txtTotalCount" Text="Gesamt: 0" FontSize="12"
                           FontWeight="SemiBold" Foreground="#1E1E2E"/>
            </Border>
            <TextBlock Grid.Column="4" x:Name="txtServer" Text="" FontSize="11"
                       Foreground="#6C7086" VerticalAlignment="Center"/>
        </Grid>

        <!-- Log -->
        <Border Grid.Row="6" Background="#181825" CornerRadius="6" BorderBrush="#45475A" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Text="Log" Foreground="#6C7086" FontSize="11"
                           Margin="10,6,0,0"/>
                <TextBox x:Name="txtLog" Grid.Row="1" IsReadOnly="True"
                         Background="Transparent" Foreground="#A6ADC8" BorderThickness="0"
                         FontFamily="Consolas" FontSize="11"
                         VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                         Margin="10,4,10,8"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# --- Window erstellen ---
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# --- Controls referenzieren ---
$btnSave = $window.FindName("btnSave")
$btnDisable = $window.FindName("btnDisable")
$btnRestore = $window.FindName("btnRestore")
$btnRefreshFiles = $window.FindName("btnRefreshFiles")
$cmbStateFiles = $window.FindName("cmbStateFiles")
$pnlStatusBanner = $window.FindName("pnlStatusBanner")
$txtStatusBanner = $window.FindName("txtStatusBanner")
$dgJobs = $window.FindName("dgJobs")
$txtLog = $window.FindName("txtLog")
$txtEnabledCount = $window.FindName("txtEnabledCount")
$txtDisabledCount = $window.FindName("txtDisabledCount")
$txtTotalCount = $window.FindName("txtTotalCount")
$txtServer = $window.FindName("txtServer")

# --- Hilfsfunktionen ---

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $txtLog.AppendText("[$timestamp] $Level - $Message`r`n")
    $txtLog.ScrollToEnd()
    # Parallel ins Log-File schreiben
    $logTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$logTimestamp] $Level - $Message" | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
    # Leeren Dispatcher-Call ausfuehren damit WPF die UI sofort aktualisiert (verhindert Einfrieren)
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Set-ButtonsEnabled {
    param([bool]$Enabled)
    $btnSave.IsEnabled = $Enabled
    $btnDisable.IsEnabled = $Enabled
    $btnRestore.IsEnabled = $Enabled
}

function Show-StatusBanner {
    param([string]$Text, [string]$Color = "#F9E2AF")
    $pnlStatusBanner.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Color)
    $txtStatusBanner.Text = $Text
    $pnlStatusBanner.Visibility = "Visible"
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Hide-StatusBanner {
    $pnlStatusBanner.Visibility = "Collapsed"
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Update-StateFileStatus {
    param([string]$FilePath, [string]$Status, [string]$Detail = "")
    if (-not $FilePath -or -not (Test-Path $FilePath)) { return }
    try {
        $data = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
        $data | Add-Member -NotePropertyName "Status" -NotePropertyValue $Status -Force
        if ($Detail) {
            $data | Add-Member -NotePropertyName "StatusDetail" -NotePropertyValue $Detail -Force
        }
        $data | Add-Member -NotePropertyName "StatusTime" -NotePropertyValue (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Force
        $data | ConvertTo-Json -Depth 5 | Out-File -FilePath $FilePath -Encoding UTF8
    }
    catch {}
}

function Update-StateFileList {
    $cmbStateFiles.Items.Clear()
    $files = Get-ChildItem -Path $ScriptDir -Filter "VeeamJobState_*.json" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending
    foreach ($file in $files) {
        $cmbStateFiles.Items.Add($file.Name) | Out-Null
    }
    if ($cmbStateFiles.Items.Count -gt 0) {
        $cmbStateFiles.SelectedIndex = 0
    }
}

function Get-SelectedStateFilePath {
    if ($cmbStateFiles.SelectedItem) {
        return Join-Path $ScriptDir $cmbStateFiles.SelectedItem
    }
    return $null
}

function Update-JobGrid {
    param($Jobs)
    $jobArray = @($Jobs)
    $displayList = New-Object System.Collections.ArrayList
    foreach ($job in ($jobArray | Sort-Object Name)) {
        $isEnabled = [bool]$job.IsEnabled
        $statusText = if ($isEnabled) { "Aktiv" } else { "Inaktiv" }
        $displayList.Add([PSCustomObject]@{
            Name       = [string]$job.Name
            Type       = [string]$job.Type
            StatusText = [string]$statusText
            IsEnabled  = $isEnabled
        }) | Out-Null
    }
    $dgJobs.ItemsSource = $displayList

    $enabled = @($jobArray | Where-Object { $_.IsEnabled -eq $true }).Count
    $disabled = @($jobArray | Where-Object { $_.IsEnabled -eq $false }).Count
    $total = $jobArray.Count
    $txtEnabledCount.Text = "Aktiv: $enabled"
    $txtDisabledCount.Text = "Inaktiv: $disabled"
    $txtTotalCount.Text = "Gesamt: $total"
}

# --- Veeam Funktionen ---

$script:VeeamLoaded = $false

function Initialize-Veeam {
    if ($script:VeeamLoaded) { return $true }

    # Pruefen ob Veeam-Cmdlets bereits verfuegbar sind (z.B. in Veeam PS Console)
    if (Get-Command "Get-VBRJob" -ErrorAction SilentlyContinue) {
        Write-Log "Veeam Cmdlets bereits verf${ue}gbar." "OK"
        $script:VeeamLoaded = $true
        return $true
    }

    # Versuch 1: PowerShell-Modul (Veeam v11+)
    try {
        Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
        Write-Log "Veeam PowerShell Modul geladen (v11+)." "OK"
        $script:VeeamLoaded = $true
        return $true
    }
    catch {
        Write-Log "Veeam Modul nicht gefunden, versuche Snap-in..." "INFO"
    }

    # Versuch 2: PSSnapin (Veeam v9/v10)
    try {
        Add-PSSnapin VeeamPSSnapIn -ErrorAction Stop
        Write-Log "Veeam PowerShell Snap-in geladen." "OK"
        $script:VeeamLoaded = $true
        return $true
    }
    catch {
        Write-Log "Weder Veeam Modul noch Snap-in verf${ue}gbar!" "FEHLER"
        [System.Windows.MessageBox]::Show(
            "Veeam PowerShell konnte nicht geladen werden.`n`nWeder das Modul (v11+) noch das Snap-in (v9/v10) wurden gefunden.`n`nBitte dieses Tool direkt auf dem Veeam Backup Server ausf${ue}hren.",
            "Veeam nicht gefunden",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $false
    }
}

function Get-AllVeeamJobs {
    $jobs = @()
    $countBefore = 0

    # --- VBRJob (Backup, Replication, File Copy) ---
    Write-Log "Suche VBR-Jobs (Backup, Replication, Copy)..."
    Get-VBRJob | ForEach-Object {
        $enabled = $_.IsScheduleEnabled
        $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
        Write-Log "  $($_.Name) | $($_.TypeToString) | $status"
        $jobs += [PSCustomObject]@{
            Name      = $_.Name
            Id        = $_.Id.ToString()
            Type      = $_.TypeToString
            IsEnabled = $enabled
            JobKind   = "VBRJob"
        }
    }
    $found = $jobs.Count - $countBefore
    $countBefore = $jobs.Count
    Write-Log "  VBRJob: $found gefunden" $(if ($found -gt 0) { "OK" } else { "INFO" })

    # Alle weiteren Job-Typen sind optional - nicht jeder Server hat welche
    # Jeder Block ist in try/catch, da Cmdlets je nach Veeam-Version fehlen koennen

    # --- Tape Jobs ---
    Write-Log "Suche Tape-Jobs..."
    try {
        Get-VBRTapeJob | ForEach-Object {
            $enabled = $_.Enabled
            $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
            Write-Log "  $($_.Name) | Tape | $status"
            $jobs += [PSCustomObject]@{
                Name      = $_.Name
                Id        = $_.Id.ToString()
                Type      = "Tape"
                IsEnabled = $enabled
                JobKind   = "VBRTapeJob"
            }
        }
        $found = $jobs.Count - $countBefore
        $countBefore = $jobs.Count
        Write-Log "  Tape: $found gefunden" $(if ($found -gt 0) { "OK" } else { "INFO" })
    }
    catch {
        Write-Log "  Tape: nicht verf${ue}gbar" "INFO"
    }

    # --- SureBackup: v12+ Get-VBRSureBackupJob, aeltere Versionen Get-VSBJob ---
    Write-Log "Suche SureBackup-Jobs..."
    try {
        $sureBackupFound = $false
        if (Get-Command "Get-VBRSureBackupJob" -ErrorAction SilentlyContinue) {
            Get-VBRSureBackupJob | ForEach-Object {
                $enabled = $_.IsScheduleEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                Write-Log "  $($_.Name) | SureBackup | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = "SureBackup"
                    IsEnabled = $enabled
                    JobKind   = "VBRSureBackupJob"
                }
            }
            $sureBackupFound = $true
        }
        if (-not $sureBackupFound -and (Get-Command "Get-VSBJob" -ErrorAction SilentlyContinue)) {
            Get-VSBJob | ForEach-Object {
                $enabled = $_.IsScheduleEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                Write-Log "  $($_.Name) | SureBackup | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = "SureBackup"
                    IsEnabled = $enabled
                    JobKind   = "VSBJob"
                }
            }
        }
        $found = $jobs.Count - $countBefore
        $countBefore = $jobs.Count
        Write-Log "  SureBackup: $found gefunden" $(if ($found -gt 0) { "OK" } else { "INFO" })
    }
    catch {
        Write-Log "  SureBackup: nicht verf${ue}gbar" "INFO"
    }

    # --- Backup Copy Jobs (ab v12 separat von Get-VBRJob) ---
    Write-Log "Suche Backup-Copy-Jobs (v12+)..."
    try {
        if (Get-Command "Get-VBRBackupCopyJob" -ErrorAction SilentlyContinue) {
            Get-VBRBackupCopyJob | ForEach-Object {
                $enabled = $_.JobEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                Write-Log "  $($_.Name) | Backup Copy | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = "Backup Copy"
                    IsEnabled = $enabled
                    JobKind   = "VBRBackupCopyJob"
                }
            }
            $found = $jobs.Count - $countBefore
            $countBefore = $jobs.Count
            Write-Log "  Backup Copy: $found gefunden" $(if ($found -gt 0) { "OK" } else { "INFO" })
        }
        else {
            Write-Log "  Backup Copy: Cmdlet nicht vorhanden (vor v12 in VBRJob enthalten)" "INFO"
        }
    }
    catch {
        Write-Log "  Backup Copy: Fehler beim Abfragen - $($_.Exception.Message)" "WARNUNG"
    }

    # --- Agent Backup Jobs ---
    Write-Log "Suche Agent-Backup-Jobs..."
    try {
        if (Get-Command "Get-VBRComputerBackupJob" -ErrorAction SilentlyContinue) {
            Get-VBRComputerBackupJob | ForEach-Object {
                $enabled = $_.JobEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                Write-Log "  $($_.Name) | Agent Backup | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = "Agent Backup"
                    IsEnabled = $enabled
                    JobKind   = "VBRComputerBackupJob"
                }
            }
            $found = $jobs.Count - $countBefore
            $countBefore = $jobs.Count
            Write-Log "  Agent Backup: $found gefunden" $(if ($found -gt 0) { "OK" } else { "INFO" })
        }
        else {
            Write-Log "  Agent Backup: Cmdlet nicht vorhanden" "INFO"
        }
    }
    catch {
        Write-Log "  Agent Backup: Fehler beim Abfragen - $($_.Exception.Message)" "WARNUNG"
    }

    # --- Agent Backup Copy Jobs ---
    Write-Log "Suche Agent-Backup-Copy-Jobs..."
    try {
        if (Get-Command "Get-VBRComputerBackupCopyJob" -ErrorAction SilentlyContinue) {
            Get-VBRComputerBackupCopyJob | ForEach-Object {
                $enabled = $_.JobEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                Write-Log "  $($_.Name) | Agent Backup Copy | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = "Agent Backup Copy"
                    IsEnabled = $enabled
                    JobKind   = "VBRComputerBackupCopyJob"
                }
            }
            $found = $jobs.Count - $countBefore
            $countBefore = $jobs.Count
            Write-Log "  Agent Backup Copy: $found gefunden" $(if ($found -gt 0) { "OK" } else { "INFO" })
        }
        else {
            Write-Log "  Agent Backup Copy: Cmdlet nicht vorhanden" "INFO"
        }
    }
    catch {
        Write-Log "  Agent Backup Copy: Fehler beim Abfragen - $($_.Exception.Message)" "WARNUNG"
    }

    # --- NAS/Unstructured Backup Jobs (v12: Unstructured, v10/v11: NAS) ---
    Write-Log "Suche NAS-Backup-Jobs..."
    try {
        if (Get-Command "Get-VBRUnstructuredBackupJob" -ErrorAction SilentlyContinue) {
            Get-VBRUnstructuredBackupJob | ForEach-Object {
                $enabled = $_.JobEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                Write-Log "  $($_.Name) | NAS Backup | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = "NAS Backup"
                    IsEnabled = $enabled
                    JobKind   = "VBRNASBackupJob"
                }
            }
            $found = $jobs.Count - $countBefore
            $countBefore = $jobs.Count
            Write-Log "  NAS Backup: $found gefunden (Unstructured-Cmdlet)" $(if ($found -gt 0) { "OK" } else { "INFO" })
        }
        elseif (Get-Command "Get-VBRNASBackupJob" -ErrorAction SilentlyContinue) {
            Get-VBRNASBackupJob | ForEach-Object {
                $enabled = $_.JobEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                Write-Log "  $($_.Name) | NAS Backup | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = "NAS Backup"
                    IsEnabled = $enabled
                    JobKind   = "VBRNASBackupJob"
                }
            }
            $found = $jobs.Count - $countBefore
            $countBefore = $jobs.Count
            Write-Log "  NAS Backup: $found gefunden (NAS-Cmdlet)" $(if ($found -gt 0) { "OK" } else { "INFO" })
        }
        else {
            Write-Log "  NAS Backup: Cmdlet nicht vorhanden" "INFO"
        }
    }
    catch {
        Write-Log "  NAS Backup: Fehler beim Abfragen - $($_.Exception.Message)" "WARNUNG"
    }

    # --- CDP Policies (Continuous Data Protection) ---
    Write-Log "Suche CDP-Policies..."
    try {
        if (Get-Command "Get-VBRCDPPolicy" -ErrorAction SilentlyContinue) {
            Get-VBRCDPPolicy | ForEach-Object {
                $enabled = $_.IsEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                Write-Log "  $($_.Name) | CDP | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = "CDP"
                    IsEnabled = $enabled
                    JobKind   = "VBRCDPPolicy"
                }
            }
            $found = $jobs.Count - $countBefore
            $countBefore = $jobs.Count
            Write-Log "  CDP: $found gefunden" $(if ($found -gt 0) { "OK" } else { "INFO" })
        }
        else {
            Write-Log "  CDP: Cmdlet nicht vorhanden" "INFO"
        }
    }
    catch {
        Write-Log "  CDP: Fehler beim Abfragen - $($_.Exception.Message)" "WARNUNG"
    }

    # --- Plugin Jobs (Oracle RMAN, SAP HANA etc.) ---
    Write-Log "Suche Plugin-Jobs (Oracle, SAP etc.)..."
    try {
        if (Get-Command "Get-VBRPluginJob" -ErrorAction SilentlyContinue) {
            Get-VBRPluginJob | ForEach-Object {
                $enabled = $_.IsScheduleEnabled
                $status = if ($enabled) { "Aktiv" } else { "Inaktiv" }
                $typeName = "Plugin ($($_.TypeToString))"
                Write-Log "  $($_.Name) | $typeName | $status"
                $jobs += [PSCustomObject]@{
                    Name      = $_.Name
                    Id        = $_.Id.ToString()
                    Type      = $typeName
                    IsEnabled = $enabled
                    JobKind   = "VBRPluginJob"
                }
            }
            $found = $jobs.Count - $countBefore
            $countBefore = $jobs.Count
            Write-Log "  Plugin: $found gefunden" $(if ($found -gt 0) { "OK" } else { "INFO" })
        }
        else {
            Write-Log "  Plugin: Cmdlet nicht vorhanden" "INFO"
        }
    }
    catch {
        Write-Log "  Plugin: Fehler beim Abfragen - $($_.Exception.Message)" "WARNUNG"
    }

    # --- Zusammenfassung ---
    $summary = $jobs | Group-Object JobKind | ForEach-Object { "$($_.Count)x $($_.Name)" }
    $enabled = @($jobs | Where-Object { $_.IsEnabled -eq $true }).Count
    $disabled = @($jobs | Where-Object { $_.IsEnabled -eq $false }).Count
    Write-Log "Gesamt: $($jobs.Count) Jobs ($enabled aktiv, $disabled inaktiv) - $($summary -join ', ')" "OK"

    return $jobs
}

# --- Button Events ---

$btnSave.Add_Click({
    Set-ButtonsEnabled $false
    try {
        if (-not (Initialize-Veeam)) { return }

        Write-Log "Lese alle Veeam Jobs..."
        $jobs = Get-AllVeeamJobs

        if ($jobs.Count -eq 0) {
            Write-Log "Keine Jobs gefunden!" "WARNUNG"
            [System.Windows.MessageBox]::Show("Keine Veeam Jobs gefunden.", "Warnung",
                [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }

        Update-JobGrid $jobs

        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
        $outFile = Join-Path $ScriptDir "VeeamJobState_${script:FQDN}_$timestamp.json"

        $state = [PSCustomObject]@{
            SavedAt    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            ServerName = $script:FQDN
            JobCount   = $jobs.Count
            Jobs       = $jobs
        }

        $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $outFile -Encoding UTF8

        $enabled = @($jobs | Where-Object { $_.IsEnabled -eq $true }).Count
        $disabled = @($jobs | Where-Object { $_.IsEnabled -eq $false }).Count

        Write-Log "$($jobs.Count) Jobs gesichert ($enabled aktiv, $disabled inaktiv)" "OK"
        Write-Log "Datei: $outFile" "OK"

        Update-StateFileList
    }
    catch {
        Write-Log "Fehler beim Speichern: $($_.Exception.Message)" "FEHLER"
    }
    finally {
        Set-ButtonsEnabled $true
    }
})

$btnDisable.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Alle aktiven Veeam Jobs werden deaktiviert.`n`nDer aktuelle Zustand wird vorher automatisch gesichert.`n`nFortfahren?",
        "Jobs deaktivieren",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Set-ButtonsEnabled $false
    try {
        if (-not (Initialize-Veeam)) { return }

        # Automatisch zuerst sichern
        Write-Log "Sichere aktuellen Zustand vor dem Deaktivieren..."
        $jobs = Get-AllVeeamJobs

        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
        $outFile = Join-Path $ScriptDir "VeeamJobState_${script:FQDN}_$timestamp.json"

        $state = [PSCustomObject]@{
            SavedAt      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            ServerName   = $script:FQDN
            JobCount     = $jobs.Count
            Status       = "InProgress"
            StatusDetail = "Disable gestartet"
            StatusTime   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Jobs         = $jobs
        }
        $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $outFile -Encoding UTF8
        $script:currentStateFile = $outFile
        Write-Log "Zustand gesichert in: $outFile" "OK"

        # Jetzt deaktivieren
        $enabledJobs = $jobs | Where-Object { $_.IsEnabled -eq $true }
        if ($enabledJobs.Count -eq 0) {
            Write-Log "Alle Jobs sind bereits deaktiviert." "INFO"
            Update-JobGrid $jobs
            return
        }

        Write-Log "Deaktiviere $($enabledJobs.Count) Jobs..."
        $successCount = 0
        $errorCount = 0

        foreach ($job in $enabledJobs) {
            try {
                switch ($job.JobKind) {
                    "VBRJob" {
                        Get-VBRJob -Name $job.Name | Disable-VBRJob | Out-Null
                    }
                    "VBRTapeJob" {
                        # Veeam bietet kein Disable-VBRTapeJob Cmdlet - Disable-VBRJob funktioniert aber auch fuer Tape-Jobs
                        Get-VBRTapeJob -Name $job.Name | Disable-VBRJob | Out-Null
                    }
                    "VBRSureBackupJob" {
                        Get-VBRSureBackupJob -Name $job.Name | Disable-VBRSureBackupJob | Out-Null
                    }
                    "VSBJob" {
                        Get-VSBJob -Name $job.Name | Set-VSBJobScheduleOptions -Enabled:$false | Out-Null
                    }
                    "VBRBackupCopyJob" {
                        Get-VBRBackupCopyJob -Name $job.Name | Disable-VBRBackupCopyJob | Out-Null
                    }
                    "VBRComputerBackupJob" {
                        Get-VBRComputerBackupJob -Name $job.Name | Disable-VBRComputerBackupJob | Out-Null
                    }
                    "VBRComputerBackupCopyJob" {
                        Get-VBRComputerBackupCopyJob -Name $job.Name | Disable-VBRComputerBackupCopyJob | Out-Null
                    }
                    "VBRNASBackupJob" {
                        # Kein eigenes Disable-Cmdlet - Disable-VBRJob funktioniert
                        $nasJob = $null
                        if (Get-Command "Get-VBRUnstructuredBackupJob" -ErrorAction SilentlyContinue) {
                            $nasJob = Get-VBRUnstructuredBackupJob | Where-Object { $_.Name -eq $job.Name }
                        } elseif (Get-Command "Get-VBRNASBackupJob" -ErrorAction SilentlyContinue) {
                            $nasJob = Get-VBRNASBackupJob | Where-Object { $_.Name -eq $job.Name }
                        }
                        if ($nasJob) { $nasJob | Disable-VBRJob | Out-Null }
                    }
                    "VBRCDPPolicy" {
                        Get-VBRCDPPolicy -Name $job.Name | Disable-VBRCDPPolicy | Out-Null
                    }
                    "VBRPluginJob" {
                        Get-VBRPluginJob -Name $job.Name | Disable-VBRPluginJob | Out-Null
                    }
                }
                Write-Log "$($job.Name) ($($job.Type)) deaktiviert" "OK"
                $successCount++
            }
            catch {
                Write-Log "$($job.Name) ($($job.Type), $($job.JobKind)): $($_.Exception.Message)" "FEHLER"
                $errorCount++
            }
        }

        Write-Log "Fertig: $successCount deaktiviert, $errorCount Fehler" $(if ($errorCount -gt 0) { "WARNUNG" } else { "OK" })

        # Grid und Dropdown sofort aktualisieren
        $currentJobs = Get-AllVeeamJobs
        Update-JobGrid $currentJobs
        Update-StateFileList

        # Laufende Jobs pruefen (nur VBRJob - Tape/SureBackup haben kein GetLastState)
        Write-Log "Pr${ue}fe auf laufende Jobs..."
        $runningJobs = @(Get-VBRJob | Where-Object { $_.GetLastState() -eq "Working" })

        if ($runningJobs.Count -gt 0) {
            $names = ($runningJobs | ForEach-Object { $_.Name }) -join "`n- "
            $waitResult = [System.Windows.MessageBox]::Show(
                "Es laufen noch $($runningJobs.Count) Jobs:`n`n- $names`n`nSoll ich warten bis diese fertig sind und sie dann automatisch deaktivieren?",
                "Laufende Jobs gefunden",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )

            if ($waitResult -eq [System.Windows.MessageBoxResult]::Yes) {
                Write-Log "Warte auf $($runningJobs.Count) laufende Jobs..." "INFO"
                $runNames = ($runningJobs | ForEach-Object { $_.Name }) -join ", "
                Show-StatusBanner "Warte auf $($runningJobs.Count) laufende Jobs: $runNames"

                # Timer statt Loop -- UI bleibt bedienbar (Fenster schliessen etc.)
                $script:watchRunningJobs = [System.Collections.ArrayList]@($runningJobs | ForEach-Object { $_.Name })
                $script:watchDisabledCount = $successCount
                $script:watchStartTime = Get-Date
                $script:watchTimer = New-Object System.Windows.Threading.DispatcherTimer
                $script:watchTimer.Interval = [TimeSpan]::FromSeconds(10)
                $script:watchTimer.Add_Tick({
                    try {
                        $allJobs = @(Get-VBRJob)
                        $stillRunning = @($allJobs | Where-Object { $_.GetLastState() -eq "Working" })

                        # Nur Jobs disablen die wir tracken und die jetzt fertig sind
                        $justFinished = @($allJobs | Where-Object {
                            $_.GetLastState() -ne "Working" -and
                            $_.IsScheduleEnabled -eq $true -and
                            $script:watchRunningJobs -contains $_.Name
                        })

                        foreach ($fJob in $justFinished) {
                            try {
                                $fJob | Disable-VBRJob | Out-Null
                                Write-Log "$($fJob.Name) fertig --> deaktiviert" "OK"
                                $script:watchRunningJobs.Remove($fJob.Name)
                                $script:watchDisabledCount++
                            }
                            catch {
                                Write-Log "$($fJob.Name) deaktivieren fehlgeschlagen: $($_.Exception.Message)" "FEHLER"
                            }
                        }

                        if ($stillRunning.Count -eq 0) {
                            $script:watchTimer.Stop()
                            $script:watchTimerActive = $false
                            Update-StateFileStatus $script:currentStateFile "Complete" "Alle Jobs deaktiviert"
                            Write-Log "Alle laufenden Jobs beendet und deaktiviert!" "OK"
                            Show-StatusBanner "Alle laufenden Jobs beendet und deaktiviert - bereit f${ue}r Update" "#A6E3A1"
                            Set-ButtonsEnabled $true

                            $updatedJobs = Get-AllVeeamJobs
                            Update-JobGrid $updatedJobs
                            Update-StateFileList

                            [System.Windows.MessageBox]::Show(
                                "$($script:watchDisabledCount) Jobs deaktiviert.`nAlle laufenden Jobs beendet und deaktiviert.`n`nDas Veeam Update kann jetzt durchgef${ue}hrt werden.`n`nNach dem Update: RESTORE druecken.",
                                "Bereit f${ue}r Update",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Information
                            )
                        }
                        else {
                            $elapsed = (Get-Date) - $script:watchStartTime
                            $waitText = "{0:mm\:ss}" -f $elapsed
                            $runNames = ($stillRunning | ForEach-Object { $_.Name }) -join ", "
                            Show-StatusBanner "Warte seit $waitText auf $($stillRunning.Count) laufende Jobs: $runNames"
                            Write-Log "Warte seit $waitText auf $($stillRunning.Count) Jobs: $runNames" "INFO"
                        }
                    }
                    catch {
                        Write-Log "Fehler beim Pr${ue}fen: $($_.Exception.Message)" "FEHLER"
                    }
                })
                $script:watchTimerActive = $true
                $runNamesForState = ($runningJobs | ForEach-Object { $_.Name }) -join ", "
                Update-StateFileStatus $script:currentStateFile "WaitingForJobs" "Warte auf: $runNamesForState"
                $script:watchTimer.Start()
                # Buttons bleiben disabled aber UI ist bedienbar (Fenster schliessen etc.)
                return
            }
            else {
                Write-Log "Warten abgebrochen. Laufende Jobs wurden NICHT deaktiviert!" "WARNUNG"
            }
        }
        else {
            Write-Log "Keine laufenden Jobs." "OK"
            Show-StatusBanner "Alle Jobs deaktiviert - bereit f${ue}r Update" "#A6E3A1"
            Update-StateFileStatus $script:currentStateFile "Complete" "Alle Jobs deaktiviert"
        }

        # Grid aktualisieren
        $updatedJobs = Get-AllVeeamJobs
        Update-JobGrid $updatedJobs
        Update-StateFileList

        Write-Log "$successCount Jobs deaktiviert." "OK"
        [System.Windows.MessageBox]::Show(
            "$successCount Jobs deaktiviert.`nKeine laufenden Jobs.`n`nDas Veeam Update kann jetzt durchgef${ue}hrt werden.`n`nNach dem Update: RESTORE druecken.",
            "Bereit f${ue}r Update",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
    }
    catch {
        Write-Log "Fehler: $($_.Exception.Message)" "FEHLER"
    }
    finally {
        if (-not $script:watchTimerActive) {
            Set-ButtonsEnabled $true
        }
    }
})

$btnRestore.Add_Click({
    Hide-StatusBanner
    $stateFilePath = Get-SelectedStateFilePath
    if (-not $stateFilePath -or -not (Test-Path $stateFilePath)) {
        [System.Windows.MessageBox]::Show(
            "Keine Zustandsdatei ausgew${ae}hlt.`n`nBitte zuerst SAVE ausf${ue}hren oder eine Datei auswaehlen.",
            "Keine Datei",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return
    }

    $stateData = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json
    $jobsToEnable = @($stateData.Jobs | Where-Object { $_.IsEnabled -eq $true })
    $jobsToKeepDisabled = @($stateData.Jobs | Where-Object { $_.IsEnabled -eq $false })

    $msg = "Zustand wieder herstellen aus:`n$($cmbStateFiles.SelectedItem)`n`n"
    $msg += "Gespeichert am: $($stateData.SavedAt)`n"
    $msg += "Server: $($stateData.ServerName)`n`n"
    $msg += "$($jobsToEnable.Count) Jobs werden aktiviert`n"
    $msg += "$($jobsToKeepDisabled.Count) Jobs bleiben deaktiviert`n`n"

    if ($stateData.ServerName -ne $script:FQDN) {
        $msg += "ACHTUNG: Zustand wurde auf '$($stateData.ServerName)' erstellt!`n`n"
    }
    $msg += "Fortfahren?"

    $result = [System.Windows.MessageBox]::Show($msg, "Zustand wieder herstellen",
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Set-ButtonsEnabled $false
    try {
        if (-not (Initialize-Veeam)) { return }

        Write-Log "Stelle Zustand wieder her aus: $($cmbStateFiles.SelectedItem)"
        $successCount = 0
        $errorCount = 0

        foreach ($job in $jobsToEnable) {
            try {
                switch ($job.JobKind) {
                    "VBRJob" {
                        Get-VBRJob -Name $job.Name | Enable-VBRJob | Out-Null
                    }
                    "VBRTapeJob" {
                        # Veeam bietet kein Enable-VBRTapeJob Cmdlet - Enable-VBRJob funktioniert aber auch fuer Tape-Jobs
                        Get-VBRTapeJob -Name $job.Name | Enable-VBRJob | Out-Null
                    }
                    "VBRSureBackupJob" {
                        Get-VBRSureBackupJob -Name $job.Name | Enable-VBRSureBackupJob | Out-Null
                    }
                    "VSBJob" {
                        Get-VSBJob -Name $job.Name | Set-VSBJobScheduleOptions -Enabled:$true | Out-Null
                    }
                    "VBRBackupCopyJob" {
                        Get-VBRBackupCopyJob -Name $job.Name | Enable-VBRBackupCopyJob | Out-Null
                    }
                    "VBRComputerBackupJob" {
                        Get-VBRComputerBackupJob -Name $job.Name | Enable-VBRComputerBackupJob | Out-Null
                    }
                    "VBRComputerBackupCopyJob" {
                        Get-VBRComputerBackupCopyJob -Name $job.Name | Enable-VBRComputerBackupCopyJob | Out-Null
                    }
                    "VBRNASBackupJob" {
                        # Kein eigenes Enable-Cmdlet - Enable-VBRJob funktioniert
                        $nasJob = $null
                        if (Get-Command "Get-VBRUnstructuredBackupJob" -ErrorAction SilentlyContinue) {
                            $nasJob = Get-VBRUnstructuredBackupJob | Where-Object { $_.Name -eq $job.Name }
                        } elseif (Get-Command "Get-VBRNASBackupJob" -ErrorAction SilentlyContinue) {
                            $nasJob = Get-VBRNASBackupJob | Where-Object { $_.Name -eq $job.Name }
                        }
                        if ($nasJob) { $nasJob | Enable-VBRJob | Out-Null }
                    }
                    "VBRCDPPolicy" {
                        Get-VBRCDPPolicy -Name $job.Name | Enable-VBRCDPPolicy | Out-Null
                    }
                    "VBRPluginJob" {
                        Get-VBRPluginJob -Name $job.Name | Enable-VBRPluginJob | Out-Null
                    }
                }
                Write-Log "$($job.Name) ($($job.Type)) --> Aktiviert" "OK"
                $successCount++
            }
            catch {
                Write-Log "$($job.Name) ($($job.Type), $($job.JobKind)): $($_.Exception.Message)" "FEHLER"
                $errorCount++
            }
        }

        # Grid aktualisieren
        $updatedJobs = Get-AllVeeamJobs
        Update-JobGrid $updatedJobs

        Write-Log "Fertig: $successCount aktiviert, $($jobsToKeepDisabled.Count) blieben deaktiviert, $errorCount Fehler" $(if ($errorCount -gt 0) { "WARNUNG" } else { "OK" })

        [System.Windows.MessageBox]::Show(
            "Wiederherstellung abgeschlossen.`n`n$successCount Jobs aktiviert`n$($jobsToKeepDisabled.Count) Jobs blieben deaktiviert`n$errorCount Fehler",
            "Ergebnis",
            [System.Windows.MessageBoxButton]::OK,
            $(if ($errorCount -gt 0) { [System.Windows.MessageBoxImage]::Warning } else { [System.Windows.MessageBoxImage]::Information })
        )
    }
    catch {
        Write-Log "Fehler: $($_.Exception.Message)" "FEHLER"
    }
    finally {
        Set-ButtonsEnabled $true
    }
})

$btnRefreshFiles.Add_Click({
    Update-StateFileList
    Write-Log "Dateiliste aktualisiert."
})

# --- Konsolenfenster verstecken ---
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

# --- Init ---
try {
    $txtServer.Text = "Server: $($script:FQDN)"
    Update-StateFileList
    $window.Title = "Veeam Job State Manager v$($script:AppVersion)"
    Write-Log "Veeam Job State Manager v$($script:AppVersion) gestartet."
    Write-Log "Arbeitsverzeichnis: $ScriptDir"

    # Wenn State-Dateien vorhanden, letzte laden und in Grid anzeigen
    $latestFile = Get-SelectedStateFilePath
    if ($latestFile -and (Test-Path $latestFile)) {
        try {
            $existingState = Get-Content -Path $latestFile -Raw | ConvertFrom-Json
            Update-JobGrid $existingState.Jobs
            Write-Log "Letzte Sicherung geladen: $($cmbStateFiles.SelectedItem) ($($existingState.SavedAt))"

            # Warnung bei abgebrochenem Vorgang
            if ($existingState.Status -eq "Aborted" -or $existingState.Status -eq "WaitingForJobs" -or $existingState.Status -eq "InProgress") {
                $detail = $existingState.StatusDetail
                Write-Log "WARNUNG: Letzter Vorgang nicht abgeschlossen! $detail" "FEHLER"
                Show-StatusBanner "WARNUNG: Letzter Vorgang nicht abgeschlossen!" "#F38BA8"
                $abortMsg = "Der letzte Disable-Vorgang wurde nicht abgeschlossen!`n`n"
                $abortMsg += "$detail`n`n"
                $abortMsg += "Diese Jobs liefen beim Abbruch noch und wurden danach nicht mehr deaktiviert.`n`n"
                $abortMsg += "Empfehlung:`n"
                $abortMsg += "- RESTORE dr" + $ue + "cken um den Originalzustand wiederherzustellen`n"
                $abortMsg += "- Oder erneut DISABLE ALL ausf" + $ue + "hren"
                $abortTitle = "Unvollst" + $ae + "ndiger Vorgang erkannt"
                [System.Windows.MessageBox]::Show(
                    $abortMsg,
                    $abortTitle,
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
            }
        }
        catch {
            Write-Log "Konnte letzte Sicherung nicht laden." "WARNUNG"
        }
    }
}
catch {
    [System.Windows.MessageBox]::Show(
        "Fehler beim Initialisieren:`n`n$($_.Exception.Message)",
        "Startfehler",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
}

# Timer stoppen wenn Fenster geschlossen wird
$window.Add_Closing({
    if ($script:watchTimer -and $script:watchTimer.IsEnabled) {
        $script:watchTimer.Stop()
        $script:watchTimerActive = $false
        $stillRunning = @($script:watchRunningJobs) -join ", "
        Update-StateFileStatus $script:currentStateFile "Aborted" "Abgebrochen. Noch laufende Jobs: $stillRunning"
    }
})

# --- Window anzeigen ---
$window.ShowDialog() | Out-Null
