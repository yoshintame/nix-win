{
  tweak,
  hkcu,
  on,
  off,
  ...
}:
let
  advanced = hkcu ''Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'';
in
{
  showFileExtensions = tweak.bool "Show extensions for known file types." (v: [
    (advanced { HideFileExt = off v; })
  ]);

  showHiddenFiles = tweak.bool "Show hidden files and folders." (v: [
    (advanced { Hidden = if v then 1 else 2; })
  ]);

  launchTo = tweak.enum {
    thisPC = 1;
    home = 2;
    downloads = 3;
    oneDrive = 4;
  } "Folder a new Explorer window opens on." (v: [ (advanced { LaunchTo = v; }) ]);

  syncProviderNotifications = tweak.bool "OneDrive and other sync provider ads in Explorer." (v: [
    (advanced { ShowSyncProviderNotifications = on v; })
  ]);
}
