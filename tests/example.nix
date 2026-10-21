_: {
  boot.isContainer = true;
  system.stateVersion = "25.05";

  windows = {
    enable = true;
    flake = "/etc/nixos#example";
    users.alice = { };

    defaults = {
      explorer.showFileExtensions = true;
      ai.copilot = false;
      system.sudo = "inline";
    };

    registry = {
      HKLM."SOFTWARE\\NixWin\\Example" = {
        Path = ''C:\Program Files (x86)\Example\app.exe'';
        Quote = ''say "hi" & 100% done\'';
        Cyrillic = "Привет";
        Monitor = ''27" monitor & (x86)'';
        Gone = null;
      };
      HKLM."SOFTWARE\\NixWin\\Removed" = null;
      HKLM."SOFTWARE\\NixWin\\Removed\\Child".Value = null;
      HKCU."Software\\NixWin\\Empty" = { };
    };

    services.Spooler.startType = "demand";
    capabilities = [ "OpenSSH.Server~~~~0.0.1.0" ];
    networkAdapters.powerManagement.WakeOnMagicPacket = "Enabled";
    firewall.rules.Example-In-TCP = {
      displayName = "Пример — Example (TCP)";
      localPort = 8080;
      remoteAddress = [ "100.64.0.0/10" ];
    };
    files."C:\\ProgramData\\NixWin\\example.conf" = {
      text = "key = value\n";
      validate = file: "findstr /b /c:key ${file} >nul";
      onChange = "echo changed";
    };
    power.timeouts.standby-timeout-ac = 0;
    scheduledTasks."\\Microsoft\\Windows\\Example\\Task".enable = false;
    winget = {
      packages = {
        "Blizzard.BattleNet".location = ''C:\Program Files (x86)\Battle.net'';
        "Notepad++.Notepad++".timeout = 120;
        "Tailscale.Tailscale" = { };
        XPDP2QW12DFSFK = {
          source = "msstore";
          name = "Example Store app";
        };
      };
      timeout = 600;
      bundle = ./bundle.json;
      bundleFile = "/home/alice/config/winget.bundle.json";
    };
  };
}
