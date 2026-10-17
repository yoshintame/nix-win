{
  tweak,
  hkcu,
  on,
  ...
}:
let
  advanced = hkcu ''Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'';
  delivery = hkcu ''Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'';
in
{
  recommendations = tweak.bool "Tips, shortcuts and new app recommendations in Start." (v: [
    (advanced { Start_IrisRecommendations = on v; })
  ]);

  trackAppLaunches = tweak.bool "Rank Start and search results by the apps you launch." (v: [
    (advanced { Start_TrackProgs = on v; })
  ]);

  suggestions = tweak.bool "App suggestions in Start." (v: [
    (delivery {
      "SubscribedContent-338388Enabled" = on v;
      SystemPaneSuggestionsEnabled = on v;
    })
  ]);
}
