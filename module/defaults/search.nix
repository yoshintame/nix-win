{
  tweak,
  hklm,
  hkcu,
  on,
  off,
  ...
}:
{
  webResults = tweak.bool "Bing web results and suggestions in Start search." (v: [
    (hkcu ''Software\Policies\Microsoft\Windows\Explorer'' { DisableSearchBoxSuggestions = off v; })
  ]);

  cortana = tweak.bool "Cortana in search." (v: [
    (hklm ''SOFTWARE\Policies\Microsoft\Windows\Windows Search'' { AllowCortana = on v; })
  ]);
}
