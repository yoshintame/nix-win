{
  tweak,
  hklm,
  hkcu,
  advanced,
  on,
  off,
  ...
}:
let
  policies = ''SOFTWARE\Policies\Microsoft\Windows'';
  userPolicies = ''Software\Policies\Microsoft\Windows'';
in
{
  copilot = tweak.bool "Windows Copilot for all users and its taskbar button." (v: [
    (hklm ''${policies}\WindowsCopilot'' { TurnOffWindowsCopilot = off v; })
    (hkcu ''${userPolicies}\WindowsCopilot'' { TurnOffWindowsCopilot = off v; })
    (advanced { ShowCopilotButton = on v; })
  ]);

  recall = tweak.bool "Recall: saving screen snapshots and their AI analysis." (v: [
    (hklm ''${policies}\WindowsAI'' {
      DisableAIDataAnalysis = off v;
      AllowRecallEnablement = on v;
      TurnOffSavingSnapshots = off v;
    })
    (hkcu ''${userPolicies}\WindowsAI'' { DisableAIDataAnalysis = off v; })
  ]);

  clickToDo = tweak.bool "Click to Do actions on screen content." (v: [
    (hklm ''${policies}\WindowsAI'' { DisableClickToDo = off v; })
    (hkcu ''${userPolicies}\WindowsAI'' { DisableClickToDo = off v; })
  ]);

  paint =
    tweak.bool
      "AI features in Paint: Cocreator, generative fill and erase, image creator, background removal."
      (v: [
        (hklm ''SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'' {
          DisableCocreator = off v;
          DisableGenerativeFill = off v;
          DisableImageCreator = off v;
          DisableGenerativeErase = off v;
          DisableRemoveBackground = off v;
        })
      ]);

  notepad = tweak.bool "AI features in Notepad." (v: [
    (hklm ''SOFTWARE\Policies\WindowsNotepad'' { DisableAIFeatures = off v; })
  ]);
}
