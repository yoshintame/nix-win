{
  tweak,
  hklm,
  hkcu,
  advanced,
  contentDelivery,
  on,
  off,
  ...
}:
let
  toast = name: hkcu ''Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\${name}'';
in
{
  welcomeExperience = tweak.bool "Windows welcome experience after updates and at sign-in." (v: [
    (contentDelivery { "SubscribedContent-310093Enabled" = on v; })
  ]);

  lockScreenTips = tweak.bool "Fun facts and tips on the lock screen." (v: [
    (contentDelivery {
      "SubscribedContent-338387Enabled" = on v;
      RotatingLockScreenOverlayEnabled = on v;
    })
  ]);

  tips = tweak.bool "Tips, tricks and suggestions while using Windows." (v: [
    (contentDelivery {
      "SubscribedContent-338389Enabled" = on v;
      SoftLandingEnabled = on v;
    })
  ]);

  settingsSuggestions = tweak.bool "Suggested content in the Settings app." (v: [
    (contentDelivery {
      "SubscribedContent-338393Enabled" = on v;
      "SubscribedContent-353694Enabled" = on v;
      "SubscribedContent-353696Enabled" = on v;
      "SubscribedContent-353698Enabled" = on v;
    })
  ]);

  settingsMicrosoft365Ads = tweak.bool "Microsoft 365 ads on the Settings home page." (v: [
    (hklm ''SOFTWARE\Policies\Microsoft\Windows\CloudContent'' {
      DisableConsumerAccountStateContent = off v;
    })
  ]);

  accountNotifications = tweak.bool "Microsoft account notifications in Start and Settings." (v: [
    (advanced {
      Start_AccountNotifications = on v;
    })
    (hkcu ''Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications'' {
      EnableAccountNotifications = on v;
    })
  ]);

  finishSetupPrompt = tweak.bool "\"Finish setting up your device\" prompts." (v: [
    (hkcu ''Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'' {
      ScoobeSystemSettingEnabled = on v;
    })
  ]);

  suggestedNotifications = tweak.bool "Notifications suggesting Microsoft services." (v: [
    (toast "Windows.SystemToast.Suggested" { Enabled = on v; })
  ]);

  backupReminders = tweak.bool "Windows Backup reminder notifications." (v: [
    (toast "Windows.SystemToast.BackupReminder" { Enabled = on v; })
  ]);

  phoneLink = tweak.bool "Suggestions to use a phone with Windows (Phone Link)." (v: [
    (hkcu ''Software\Microsoft\Windows\CurrentVersion\Mobility'' { OptedIn = on v; })
  ]);

  silentAppInstalls = tweak.bool "Silent installation of promoted apps." (v: [
    (contentDelivery { SilentInstalledAppsEnabled = on v; })
  ]);
}
