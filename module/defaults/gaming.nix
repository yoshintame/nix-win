{
  tweak,
  hklm,
  hkcu,
  on,
  ...
}:
{
  gameDvr = tweak.bool "Game DVR and Game Bar background recording." (v: [
    (hklm ''SOFTWARE\Policies\Microsoft\Windows\GameDVR'' { AllowGameDVR = on v; })
    (hkcu ''System\GameConfigStore'' { GameDVR_Enabled = on v; })
    (hkcu ''Software\Microsoft\Windows\CurrentVersion\GameDVR'' { AppCaptureEnabled = on v; })
  ]);
}
