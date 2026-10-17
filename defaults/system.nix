{
  tweak,
  hklm,
  on,
  off,
  service,
  tasks,
  ...
}:
{
  sudo =
    tweak.enum
      {
        disabled = 0;
        newWindow = 1;
        inputDisabled = 2;
        inline = 3;
      }
      "Mode of the built-in sudo.exe; windows-rebuild needs inline to see the output and exit code of apply.cmd."
      (v: [ (hklm ''SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo'' { Enabled = v; }) ]);

  developerMode = tweak.bool "Developer mode: sideloading and symlinks without elevation." (v: [
    (hklm ''SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'' {
      AllowDevelopmentWithoutDevLicense = on v;
    })
  ]);

  errorReporting = tweak.bool "Windows Error Reporting service and its report queue task." (v: [
    (service "WerSvc" v)
    (tasks [ ''\Microsoft\Windows\Windows Error Reporting\QueueReporting'' ] v)
  ]);

  deviceMetadataDownload = tweak.bool "Download vendor apps and icons for connected devices." (v: [
    (hklm ''SOFTWARE\Policies\Microsoft\Windows\Device Metadata'' {
      PreventDeviceMetadataFromNetwork = off v;
    })
  ]);
}
