{
  tweak,
  hklm,
  hkcu,
  on,
  off,
  service,
  tasks,
  ...
}:
{
  telemetry =
    tweak.enum "Diagnostic data level sent to Microsoft; Pro treats lower levels as required."
      {
        required = 1;
        optional = 3;
      }
      (v: [ (hklm ''SOFTWARE\Policies\Microsoft\Windows\DataCollection'' { AllowTelemetry = v; }) ]);

  telemetryService = tweak.bool "Connected User Experiences and Telemetry service (DiagTrack)." (v: [
    (service "DiagTrack" "auto" v)
  ]);

  telemetryTasks =
    tweak.bool
      "Scheduled tasks that collect program inventory, CEIP, disk diagnostic and feedback data."
      (v: [
        (tasks [
          ''\Microsoft\Windows\Application Experience\ProgramDataUpdater''
          ''\Microsoft\Windows\Autochk\Proxy''
          ''\Microsoft\Windows\Customer Experience Improvement Program\Consolidator''
          ''\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip''
          ''\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector''
          ''\Microsoft\Windows\Feedback\Siuf\DmClient''
          ''\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload''
        ] v)
      ]);

  advertisingId = tweak.bool "Advertising ID for personalized ads in apps." (v: [
    (hkcu ''Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'' { Enabled = on v; })
  ]);

  tailoredExperiences = tweak.bool "Tips and ads tailored by diagnostic data." (v: [
    (hkcu ''Software\Microsoft\Windows\CurrentVersion\Privacy'' {
      TailoredExperiencesWithDiagnosticDataEnabled = on v;
    })
  ]);

  activityHistory = tweak.bool "Activity history published to Microsoft." (v: [
    (hklm ''SOFTWARE\Policies\Microsoft\Windows\System'' { PublishUserActivities = on v; })
  ]);

  onlineSpeechRecognition = tweak.bool "Online speech recognition." (v: [
    (hkcu ''Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'' { HasAccepted = on v; })
  ]);

  inkingAndTypingImprovement = tweak.bool "Send inking and typing data to improve recognition." (v: [
    (hkcu ''Software\Microsoft\Input\TIPC'' { Enabled = on v; })
  ]);

  inkingAndTypingPersonalization =
    tweak.bool "Personal dictionary from handwriting, typing and contacts."
      (v: [
        (hkcu ''Software\Microsoft\InputPersonalization'' {
          RestrictImplicitInkCollection = off v;
          RestrictImplicitTextCollection = off v;
        })
        (hkcu ''Software\Microsoft\InputPersonalization\TrainedDataStore'' { HarvestContacts = on v; })
        (hkcu ''Software\Microsoft\Personalization\Settings'' { AcceptedPrivacyPolicy = on v; })
      ]);

  feedbackPrompts = tweak.bool "Windows feedback prompts; false sets their frequency to never." (v: [
    (hkcu ''Software\Microsoft\Siuf\Rules'' {
      NumberOfSIUFInPeriod = if v then null else 0;
      PeriodInNanoSeconds = null;
    })
  ]);
}
