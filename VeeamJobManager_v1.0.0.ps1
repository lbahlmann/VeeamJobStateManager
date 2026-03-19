<#
.SYNOPSIS
    Veeam Job State Manager - GUI Tool zum Sichern, Deaktivieren und Wiederherstellen von Job-Zustaenden.
.DESCRIPTION
    WPF-basiertes GUI Tool fuer Veeam Update-Szenarien.
    Sichert den Enabled/Disabled-Zustand aller Veeam Jobs, deaktiviert alle fuer das Update,
    und stellt den Originalzustand danach wieder her.
.NOTES
    Version: 1.0.0
    Autor:   badata GmbH
    Datei:   VeeamJobManager_v1.0.0.ps1
#>

$script:AppVersion = "1.0.0"

# --- WPF laden ---
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- Konfiguration ---
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- XAML GUI Definition ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Veeam Job State Manager v1.0.0"
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
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
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
            <TextBlock Text="Job-Zustaende sichern, deaktivieren und wiederherstellen"
                       FontSize="12" Foreground="#6C7086" Margin="0,4,0,0"/>
        </StackPanel>

        <!-- Buttons -->
        <Grid Grid.Row="1" Margin="0,0,0,16">
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
                    <TextBlock Text="&#x1F4BE; SAVE" FontSize="16" FontWeight="Bold"
                               HorizontalAlignment="Center" Foreground="#89B4FA"/>
                    <TextBlock Text="Zustand dokumentieren" FontSize="11"
                               HorizontalAlignment="Center" Foreground="#A6ADC8"/>
                </StackPanel>
            </Button>

            <Button x:Name="btnDisable" Grid.Column="2" Style="{StaticResource ActionButton}"
                    Background="#45475A">
                <StackPanel>
                    <TextBlock Text="&#x26D4; DISABLE ALL" FontSize="16" FontWeight="Bold"
                               HorizontalAlignment="Center" Foreground="#F9E2AF"/>
                    <TextBlock Text="Alle Jobs deaktivieren" FontSize="11"
                               HorizontalAlignment="Center" Foreground="#A6ADC8"/>
                </StackPanel>
            </Button>

            <Button x:Name="btnRestore" Grid.Column="4" Style="{StaticResource ActionButton}"
                    Background="#45475A">
                <StackPanel>
                    <TextBlock Text="&#x2705; RESTORE" FontSize="16" FontWeight="Bold"
                               HorizontalAlignment="Center" Foreground="#A6E3A1"/>
                    <TextBlock Text="Zustand wiederherstellen" FontSize="11"
                               HorizontalAlignment="Center" Foreground="#A6ADC8"/>
                </StackPanel>
            </Button>
        </Grid>

        <!-- State File Auswahl -->
        <Grid Grid.Row="2" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Zustandsdatei:" Foreground="#A6ADC8"
                       VerticalAlignment="Center" Margin="0,0,8,0" FontSize="12"/>
            <ComboBox x:Name="cmbStateFiles" Grid.Column="1" Height="30" FontSize="12"
                      Background="#313244" Foreground="#CDD6F4" BorderBrush="#45475A"/>
            <Button x:Name="btnRefreshFiles" Grid.Column="2" Content="&#x1F504;" Width="30" Height="30"
                    Background="#45475A" Foreground="#CDD6F4" BorderThickness="0" Cursor="Hand"
                    Margin="8,0,0,0" FontSize="14"/>
        </Grid>

        <!-- Job-Tabelle -->
        <DataGrid x:Name="dgJobs" Grid.Row="3" Margin="0,0,0,12"
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
        <Grid Grid.Row="4" Margin="0,0,0,8">
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
        <Border Grid.Row="5" Background="#181825" CornerRadius="6" BorderBrush="#45475A" BorderThickness="1">
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
    $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Set-ButtonsEnabled {
    param([bool]$Enabled)
    $btnSave.IsEnabled = $Enabled
    $btnDisable.IsEnabled = $Enabled
    $btnRestore.IsEnabled = $Enabled
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
        Write-Log "Veeam Cmdlets bereits verfuegbar." "OK"
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
        Write-Log "Weder Veeam Modul noch Snap-in verfuegbar!" "FEHLER"
        [System.Windows.MessageBox]::Show(
            "Veeam PowerShell konnte nicht geladen werden.`n`nWeder das Modul (v11+) noch das Snap-in (v9/v10) wurden gefunden.`n`nBitte dieses Tool direkt auf dem Veeam Backup Server ausfuehren.",
            "Veeam nicht gefunden",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $false
    }
}

function Get-AllVeeamJobs {
    $jobs = @()

    Get-VBRJob | ForEach-Object {
        $jobs += [PSCustomObject]@{
            Name      = $_.Name
            Id        = $_.Id.ToString()
            Type      = $_.TypeToString
            IsEnabled = $_.IsScheduleEnabled
            JobKind   = "VBRJob"
        }
    }

    try {
        Get-VBRTapeJob | ForEach-Object {
            $jobs += [PSCustomObject]@{
                Name      = $_.Name
                Id        = $_.Id.ToString()
                Type      = "Tape"
                IsEnabled = $_.Enabled
                JobKind   = "VBRTapeJob"
            }
        }
    }
    catch {
        Write-Log "Keine Tape-Jobs gefunden." "INFO"
    }

    try {
        Get-VSBJob | ForEach-Object {
            $jobs += [PSCustomObject]@{
                Name      = $_.Name
                Id        = $_.Id.ToString()
                Type      = "SureBackup"
                IsEnabled = $_.IsScheduleEnabled
                JobKind   = "VSBJob"
            }
        }
    }
    catch {
        Write-Log "Keine SureBackup-Jobs gefunden." "INFO"
    }

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
        $outFile = Join-Path $ScriptDir "VeeamJobState_$timestamp.json"

        $state = [PSCustomObject]@{
            SavedAt    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            ServerName = $env:COMPUTERNAME
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
        $outFile = Join-Path $ScriptDir "VeeamJobState_$timestamp.json"

        $state = [PSCustomObject]@{
            SavedAt    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            ServerName = $env:COMPUTERNAME
            JobCount   = $jobs.Count
            Jobs       = $jobs
        }
        $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $outFile -Encoding UTF8
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
                        Get-VBRTapeJob -Name $job.Name | Disable-VBRTapeJob | Out-Null
                    }
                    "VSBJob" {
                        $sureJob = Get-VSBJob -Name $job.Name
                        $sureJob | Set-VSBJobScheduleOptions -Enabled:$false | Out-Null
                    }
                }
                Write-Log "$($job.Name) deaktiviert" "OK"
                $successCount++
            }
            catch {
                Write-Log "$($job.Name): $($_.Exception.Message)" "FEHLER"
                $errorCount++
            }
        }

        Write-Log "Fertig: $successCount deaktiviert, $errorCount Fehler" $(if ($errorCount -gt 0) { "WARNUNG" } else { "OK" })

        # Laufende Jobs stoppen
        Write-Log "Pruefe auf laufende Jobs..."
        $runningJobs = @(Get-VBRJob | Where-Object { $_.GetLastState() -eq "Working" })
        $stoppedCount = 0
        $stopErrors = 0

        if ($runningJobs.Count -gt 0) {
            Write-Log "$($runningJobs.Count) Jobs laufen noch, stoppe diese..." "INFO"
            foreach ($rJob in $runningJobs) {
                try {
                    Write-Log "Stoppe $($rJob.Name)..." "INFO"
                    Stop-VBRJob -Job $rJob | Out-Null
                    Write-Log "$($rJob.Name) gestoppt" "OK"
                    $stoppedCount++
                }
                catch {
                    Write-Log "$($rJob.Name) stoppen fehlgeschlagen: $($_.Exception.Message)" "FEHLER"
                    $stopErrors++
                }
            }

            # Warten bis alle Jobs wirklich gestoppt sind
            Write-Log "Warte auf Beendigung der Jobs..."
            $maxWait = 120
            $waited = 0
            while ($waited -lt $maxWait) {
                $stillRunning = @(Get-VBRJob | Where-Object { $_.GetLastState() -eq "Working" })
                if ($stillRunning.Count -eq 0) { break }
                Write-Log "Noch $($stillRunning.Count) Jobs aktiv, warte... ($waited s)" "INFO"
                Start-Sleep -Seconds 5
                $waited += 5
                $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
            }

            if ($waited -ge $maxWait) {
                $stillRunning = @(Get-VBRJob | Where-Object { $_.GetLastState() -eq "Working" })
                if ($stillRunning.Count -gt 0) {
                    $names = ($stillRunning | ForEach-Object { $_.Name }) -join ", "
                    Write-Log "TIMEOUT: Diese Jobs laufen noch: $names" "WARNUNG"
                }
            }
        }
        else {
            Write-Log "Keine laufenden Jobs gefunden." "OK"
        }

        # Grid aktualisieren
        $updatedJobs = Get-AllVeeamJobs
        Update-JobGrid $updatedJobs
        Update-StateFileList

        $summary = "$successCount Jobs deaktiviert"
        if ($stoppedCount -gt 0) { $summary += ", $stoppedCount gestoppt" }
        if (($errorCount + $stopErrors) -gt 0) { $summary += ", $($errorCount + $stopErrors) Fehler" }
        Write-Log $summary "OK"

        $msgText = "$successCount Jobs deaktiviert."
        if ($stoppedCount -gt 0) { $msgText += "`n$stoppedCount laufende Jobs gestoppt." }
        $msgText += "`n`nDas Veeam Update kann jetzt durchgefuehrt werden.`n`nNach dem Update: RESTORE druecken."

        [System.Windows.MessageBox]::Show(
            $msgText,
            "Erfolgreich",
            [System.Windows.MessageBoxButton]::OK,
            $(if (($errorCount + $stopErrors) -gt 0) { [System.Windows.MessageBoxImage]::Warning } else { [System.Windows.MessageBoxImage]::Information })
        )
    }
    catch {
        Write-Log "Fehler: $($_.Exception.Message)" "FEHLER"
    }
    finally {
        Set-ButtonsEnabled $true
    }
})

$btnRestore.Add_Click({
    $stateFilePath = Get-SelectedStateFilePath
    if (-not $stateFilePath -or -not (Test-Path $stateFilePath)) {
        [System.Windows.MessageBox]::Show(
            "Keine Zustandsdatei ausgewaehlt.`n`nBitte zuerst SAVE ausfuehren oder eine Datei auswaehlen.",
            "Keine Datei",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return
    }

    $stateData = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json
    $jobsToEnable = @($stateData.Jobs | Where-Object { $_.IsEnabled -eq $true })
    $jobsToKeepDisabled = @($stateData.Jobs | Where-Object { $_.IsEnabled -eq $false })

    $msg = "Zustand wiederherstellen aus:`n$($cmbStateFiles.SelectedItem)`n`n"
    $msg += "Gespeichert am: $($stateData.SavedAt)`n"
    $msg += "Server: $($stateData.ServerName)`n`n"
    $msg += "$($jobsToEnable.Count) Jobs werden aktiviert`n"
    $msg += "$($jobsToKeepDisabled.Count) Jobs bleiben deaktiviert`n`n"

    if ($stateData.ServerName -ne $env:COMPUTERNAME) {
        $msg += "ACHTUNG: Zustand wurde auf '$($stateData.ServerName)' erstellt!`n`n"
    }
    $msg += "Fortfahren?"

    $result = [System.Windows.MessageBox]::Show($msg, "Zustand wiederherstellen",
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
                        Get-VBRTapeJob -Name $job.Name | Enable-VBRTapeJob | Out-Null
                    }
                    "VSBJob" {
                        $sureJob = Get-VSBJob -Name $job.Name
                        $sureJob | Set-VSBJobScheduleOptions -Enabled:$true | Out-Null
                    }
                }
                Write-Log "$($job.Name) --> Aktiviert" "OK"
                $successCount++
            }
            catch {
                Write-Log "$($job.Name): $($_.Exception.Message)" "FEHLER"
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
    $txtServer.Text = "Server: $($env:COMPUTERNAME)"
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

# --- Window anzeigen ---
$window.ShowDialog() | Out-Null
