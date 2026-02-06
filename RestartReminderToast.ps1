param (
    [string]$Uri
)

# Handle protocol URI
if ($Uri) {
    if ($Uri -eq 'RestartScript:') {
        shutdown /r /f /t 0
        exit
    }
}

# Get last reboot time
$Last_reboot = Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty LastBootUpTime
$Check_FastBoot = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ErrorAction SilentlyContinue).HiberbootEnabled

if (($Check_FastBoot -eq $null) -or ($Check_FastBoot -eq 0)) {
    $Boot_Event = Get-WinEvent -ProviderName 'Microsoft-Windows-Kernel-Boot' -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq 27 -and $_.Message -like "*0x0*" }
    if ($Boot_Event) { $Last_boot = $Boot_Event[0].TimeCreated }
} elseif ($Check_FastBoot -eq 1) {
    $Boot_Event = Get-WinEvent -ProviderName 'Microsoft-Windows-Kernel-Boot' -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq 27 -and $_.Message -like "*0x1*" }
    if ($Boot_Event) { $Last_boot = $Boot_Event[0].TimeCreated }
}

$Uptime = if ($Last_boot) { if ($Last_reboot -gt $Last_boot) { $Last_reboot } else { $Last_boot } } else { $Last_reboot }
$Days = ((Get-Date) - $Uptime).Days

# Protocol for restart action
$ActionProtocol = 'RestartScript'
$RestartScript = 'shutdown /r /f /t 0'
$RestartPath = "$env:TEMP\RestartScript.cmd"
$RegPath = "HKCU:\SOFTWARE\Classes\$ActionProtocol\shell\open\command"

$RestartScript | Out-File $RestartPath -Encoding ASCII -Force
New-Item -Path $RegPath -Force | Out-Null
New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\$ActionProtocol" -Name "URL Protocol" -Value "" -Force | Out-Null
Set-ItemProperty -Path $RegPath -Name "(Default)" -Value $RestartPath -Force

# Notification configuration
$Scenario = "reminder"
$Audio = ""
$Progress = ""
$Branding = ""

switch ($Days) {

    {$_ -ge 5} {
        $Title = "Restart Required"
        $Message = "Your computer has not restarted in $Days days. Your PC will restart automatically in 15 minutes unless snoozed."

        $Audio = '<audio src="ms-winsoundevent:Notification.Looping.Alarm4" loop="true" />'

        $Buttons = @"
<input id="snoozetime" type="selection" defaultInput="15">
    <selection id="15" content="15 minutes" />
    <selection id="60" content="1 hour" />
    <selection id="240" content="4 hours" />
    <selection id="1440" content="1 day" />
</input>
<action activationType="system" arguments="snooze" hint-inputId="snoozetime" content="Snooze" />
<action activationType="protocol" arguments="${ActionProtocol}:" content="Restart Now" />
"@

        shutdown /a
        shutdown /r /f /t 900
        break
    }

    {$_ -ge 4} {
        $Title = "Restart Reminder"
        $Message = "It has been $Days days since your PC was last rebooted. Please restart your computer."
        $Audio = '<audio src="ms-winsoundevent:Notification.Reminder" />'
        $Buttons = @"
<action activationType="protocol" arguments="${ActionProtocol}:" content="Restart Now" />
"@
        break
    }

    {$_ -ge 3} {
        $Title = "Restart Reminder"
        $Message = "It has been $Days days since your PC was last rebooted. Restart recommended."
        $Audio = '<audio src="ms-winsoundevent:Notification.SMS" />'
        $Buttons = @"
<action activationType="protocol" arguments="${ActionProtocol}:" content="Restart Now" />
"@
        break
    }

    {$_ -ge 2} {
        $Title = "Restart Reminder"
        $Message = "Your computer has been running for $Days days. Please consider restarting."
        $Audio = '<audio src="ms-winsoundevent:Notification.Default" />'
        $Buttons = @"
<action activationType="protocol" arguments="Dismiss" content="Dismiss" />
"@
        break
    }

    default { exit }
}

[xml]$Toast = @"
<toast scenario="$Scenario">
  <visual>
    <binding template="ToastGeneric">
      <text>$Title</text>
      <text>$Message</text>
      $Progress
      $Branding
    </binding>
  </visual>
  $Audio
  <actions>
    $Buttons
  </actions>
</toast>
"@

# Register application for notifications
$AppID = "RestartReminder"
$DisplayName = "Restart Reminder"
$NotifRegPath = "HKCU:\Software\Classes\AppUserModelId\$AppID"
New-Item -Path $NotifRegPath -Force | Out-Null
New-ItemProperty -Path $NotifRegPath -Name DisplayName -Value $DisplayName -PropertyType String -Force | Out-Null
New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\$AppID" -Name 'ShowInActionCenter' -Value 1 -PropertyType DWORD -Force | Out-Null

# Display notification
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
$ToastXml = New-Object Windows.Data.Xml.Dom.XmlDocument
$ToastXml.LoadXml($Toast.OuterXml)

$Notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppID)
$Notification = New-Object Windows.UI.Notifications.ToastNotification $ToastXml
$Notifier.Show($Notification)
