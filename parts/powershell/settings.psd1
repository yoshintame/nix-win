@{
  Rules = @{
    PSUseCompatibleSyntax = @{
      Enable = $true
      TargetVersions = @('5.1')
    }
    PSPlaceOpenBrace = @{
      Enable = $true
      OnSameLine = $true
      NewLineAfter = $true
      IgnoreOneLineBlock = $true
    }
    PSPlaceCloseBrace = @{
      Enable = $true
      NewLineAfter = $false
      IgnoreOneLineBlock = $true
      NoEmptyLineBefore = $false
    }
    PSUseConsistentIndentation = @{
      Enable = $true
      Kind = 'space'
      IndentationSize = 2
      PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
    }
    PSUseConsistentWhitespace = @{
      Enable = $true
      CheckInnerBrace = $true
      CheckOpenBrace = $true
      CheckOpenParen = $true
      CheckOperator = $true
      CheckPipe = $true
      CheckSeparator = $true
      CheckParameter = $false
    }
    PSUseCorrectCasing = @{
      Enable = $true
    }
  }
}
