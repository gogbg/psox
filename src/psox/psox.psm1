using namespace System.Management.Automation
using namespace System.Management.Automation.Language

class pxTarget
{
    [string]$DisplayName
    [string]$Name
    [string]$Endpoint
    [string]$ConnectionId

    [void]InitializeConnectionId([hashtable]$Parameters)
    {
        #calculate ConnectionId
        $connectionParamString = $this.psobject.Properties.Where( { $_.Name -notin 'Name', 'Endpoint', 'DisplayName', 'connectionId' }) | Select-Object -Property Name, Value | ConvertTo-Json -Compress -Depth 3
        $enc = [system.Text.Encoding]::UTF8
        $connectionParamStream = [IO.MemoryStream]::new($enc.GetBytes($connectionParamString))
        $connectionParamHash = Get-FileHash -InputStream $connectionParamStream -Algorithm SHA1
        $this.ConnectionId = "$($this.Endpoint)/$($connectionParamHash.Hash)"
    }

    [string]ToString()
    {
        return $this.DisplayName
    }
}

class pxTaskState
{
    [bool]$InDesiredState
    [bool]$RebootRequired
    [bool]$Tested
    [bool]$Updated

    [string]ToString()
    {
        $result = 'Unknown'
        if ($this.Updated -and $this.InDesiredState)
        {
            $result = 'Remediated'
        }
        elseif ($this.Updated -and (-not $this.InDesiredState))
        {
            $result = 'Updated'
        }
        elseif ($this.Tested -and (-not $this.InDesiredState))
        {
            $result = 'NotInDesiredState'
        }
        elseif ($this.Tested -and $this.InDesiredState)
        {
            $result = 'OK'
        }
        
        if ($this.RebootRequired)
        {
            $result += ' (RebootRequired)'
        }
        return $result
    }
}

class pxEvent
{
    pxEvent([string]$Action, [string]$Type, [string]$Data)
    {
        $this.Timestamp = [datetime]::Now
        $this.Action = $Action
        $this.Type = $Type
        $this.Data = $Data
    }
    [datetime]$Timestamp
    [string]$Action
    [string]$Type
    [string]$Data
}

class pxTaskName
{
    [string]$Name
    [string]$SourceType
    [string]$SourceName

    [string]ToString()
    {
        $result = $this.Name
        if ($this.SourceType -and ($this.SourceType -eq 'pxRole'))
        {
            $result = "[$($this.SourceName)]$result"
        }
        return $result
    }
}

class pxFatory
{
    static [pxTask]CreateTask([string]$Name, [hashtable]$Parameters, [type]$TaskType , [type]$TargetType, [pxExectuionContext]$PsoxExecutionContext)
    {
        $result = $TaskType::new()
        $result.Name.Name = $Name
        $result.Name.SourceType = $PsoxExecutionContext.CurrentParserType
        if ($PsoxExecutionContext.CurrentParserName)
        {
            $result.Name.SourceName = $PsoxExecutionContext.CurrentParserName
        }
        $result.Target = [pxFatory]::CreateTarget($TargetType, $Parameters.Target)
        $Parameters.Remove('Target')
        $result.Parameters = $Parameters
        return $result
    }

    static [pxTarget]CreateTarget([type]$Type, [hashtable]$Parameters)
    {
        $result = $Type::new($Parameters)
        $result.Name = $Parameters['Name']
        if ($Parameters.ContainsKey('Endpoint'))
        {
            $result.Endpoint = $Parameters['Endpoint']
            $result.DisplayName = "$($Parameters['Name'])/$($Parameters['Endpoint'])"
        }
        else
        {
            $result.Endpoint = $Parameters['Name']
            $result.DisplayName = $Parameters['Name']
        }
        $result.InitializeConnectionId($Parameters)

        return $result
    }
    static [pxTarget]CreateTarget([type]$Type, [string]$Name)
    {
        $result = [pxFatory]::CreateTarget($Type, @{Name = $Name })
        return $result
    }
}

class pxTask
{
    [pxTaskName]$Name = [pxTaskName]::new()
    [pxTarget]$Target
    hidden [hashtable]$Parameters
    hidden [object]$Output
    hidden [System.Collections.Generic.List[pxEvent]]$Log = [System.Collections.Generic.List[pxEvent]]::New()
    [pxTaskState]$State = [pxTaskState]::new()

    [void]Connect()
    {
        throw 'Not implemented'
    }

    [void]Prepare()
    {
        throw 'Not implemented'
    }

    [void]Test()
    {
        throw 'Not implemented'
    }

    [void]Set()
    {
        throw 'Not implemented'
    }

    [void]LogError([string]$Action, [string]$Data)
    {
        $this.Log.Add([pxEvent]::new($Action, 'Error', $Data))
        throw "$($this.Name)::$($this.Target) - $Action - Error - $Data"
    }

    [void]LogInformation([string]$Action, [string]$Data)
    {
        $this.Log.Add([pxEvent]::new($Action, 'Information', $Data))
        Write-Information -MessageData "$($this.Name)::$($this.Target) - $Action - $Data"
    }
}

class pxConnectionManager
{
    static [bool]ConnectionExist([string]$Id)
    {
        return [pxConnectionManager]::ConnectionCache.ContainsKey($Id)
    }

    static [void]AddConnection([string]$Id, [psobject]$Connection)
    {
        [pxConnectionManager]::ConnectionCache[$Id] = $Connection
    }

    static [psobject]GetConnection([string]$Id)
    {
        if ([pxConnectionManager]::ConnectionExist($Id))
        {
            return [pxConnectionManager]::ConnectionCache[$Id]
        }
        else
        {
            throw "Connection: '$Id' not found"
        }
    }

    static [hashtable]$ConnectionCache = @{}
}

class pxExectuionContext
{
    [string]$CurrentParserType
    [string]$CurrentParserName
    [string]$RootFolder
}

function Resolve-PsoxPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathFullyQualified($Path))
    {
        $fullPath = $Path
    }
    else
    {
        $fullPath = Join-Path $pxExecutionContext.RootFolder -ChildPath $Path
    }
    if (Test-Path -Path $fullPath)
    {
        $fullPath
    }
    else
    {
        throw "Path: '$Path' not found"
    }
}

function Test-PsoxPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )
    try
    {
        $null = Resolve-PsoxPath -Path $Path
        $true
    }
    catch
    {
        $false
    }
}

function Invoke-PsoxTask
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [pxTask[]]$Task,

        [Parameter(Mandatory)]
        [ValidateSet('Test', 'Set')]
        [string]$Mode
    )
    begin
    {
        $ProgressPreference = 'SilentlyContinue'

        #Invoke Connect
        foreach ($t in $task)
        {
            $t.Connect()
        }
    }
    process
    {
        foreach ($t in $task)
        {
            #Evaluate runtime parameters
            $taskType = $t.GetType().Name
            $taskSpec = $pxTaskSpec[$taskType]
            foreach ($p in $t.Parameters.Keys.Clone())
            {
                if (($t.Parameters[$p] -is [scriptblock]) -and $taskSpec.Parameters[$p].AllowRuntimeEvaluation)
                {
                    $t.Parameters[$p] = $t.Parameters[$p].InvokeWithContext($null, [psvariable]::new('allPxTasks', $Task)) | Select-Object -First 1
                }
            }

            #Invoke Prepare
            $t.Prepare()

            #Invoke Test
            $t.Test()

            #Invoke Set
            if (-not $t.State.InInDesiredState)
            {
                $t.Set()
            }
        }
    }
    end
    {
        $task
    }
}

function Test-PsoxTaskDeclaration
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Management.Automation.Language.CommandAst[]]$TaskAst
    )
    begin
    {
        $parseErrors = [System.Collections.Generic.List[ParseError]]::new()
    }
    process
    {
        foreach ($ta in $TaskAst)
        {
            $taskSpec = $pxTaskSpec[$ta.GetCommandName()]

            #Validate Syntax
            if ($ta.CommandElements[1].GetType() -notin [ExpandableStringExpressionAst], [StringConstantExpressionAst])
            {
                $parseErrors.Add([ParseError]::new($ta.Extent, 'MissingTaskName', "Missing or invalid task name. Syntax:$([System.Environment]::NewLine)$($taskSpec.Syntax)"))
            }
            if ($ta.CommandElements[2].GetType() -ne [HashtableAst])
            {
                $parseErrors.Add([ParseError]::new($ta.Extent, 1, "Missing task parameters. Syntax:$([System.Environment]::NewLine)$($taskSpec.Syntax)"))
            }

            #Validate parameters
            $mandatoryParamsReq = [System.Collections.Generic.List[string]]::new()
            foreach ($p in $taskSpec.Parameters.keys)
            {
                if ($taskSpec.Parameters[$p].Mandatory)
                {
                    $mandatoryParamsReq.Add($p)
                }
            }
            foreach ($kvp in $ta.CommandElements[2].KeyValuePairs)
            {
                #check if parameter is allowed
                if ($taskSpec.Parameters.ContainsKey($kvp.Item1.Value))
                {
                    #Validate parameter value type
                    $kvpPureExp = $kvp.Item2.GetPureExpression()
                    if ($kvpPureExp.GetType() -notin $taskSpec.Parameters[$kvp.Item1.Value].Type)
                    {
                        $parseErrors.Add([ParseError]::new($kvp.Item2.Extent, 1, "Invalid task parameter construct: '$($kvpPureExp.GetType().Name)'. Syntax:$([System.Environment]::NewLine)$($taskSpec.Syntax)"))
                    }
                    else
                    {
                        #Validate filepath
                        if ($taskSpec.Parameters[$kvp.Item1.Value].IsFilePath)
                        {
                            if (-not (Test-PsoxPath -Path $kvpPureExp.Value))
                            {
                                $parseErrors.Add([ParseError]::new($kvp.Item2.Extent, 1, "Invalid task parameter '$($kvp.Item1.Value)' value. File: '$($kvpPureExp.Value)' not found. Syntax:$([System.Environment]::NewLine)$($taskSpec.Syntax)"))
                            }
                        }
                    }
                }
                else
                {
                    $parseErrors.Add([ParseError]::new($kvp.Item1.Extent, 1, "Invalid task parameter name: '$($kvp.Item1.Value)'. Syntax:$([System.Environment]::NewLine)$($taskSpec.Syntax)"))
                }
                #mark that mandatory parameter is being used
                if ($taskSpec.Parameters[$kvp.Item1.Value].Mandatory)
                {
                    $null = $mandatoryParamsReq.Remove($kvp.Item1.Value)
                }
            }
            if ($mandatoryParamsReq.Count -gt 0)
            {
                $parseErrors.Add([ParseError]::new($ta.CommandElements[2].Extent, 1, "Missing mandatory task parameter: '$($mandatoryParamsReq -join ''', ''')'. Syntax:$([System.Environment]::NewLine)$($taskSpec.Syntax)"))
            }
        }
    }
    end
    {
        if ($parseErrors.Count -gt 0)
        {
            throw [ParseException]::new($parseErrors)
        }
    }
}

function pxScenario
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$Body,

        [Parameter()]
        [ValidateSet('Test', 'Set', 'Parse')]
        [string]$Mode = 'Parse'
    )

    $pxExecutionContext = [pxExectuionContext]@{
        CurrentParserType = 'pxScenario'
        CurrentParserName = $Name
        RootFolder        = Split-Path $Body.File -Parent
    }

    #validate body
    Get-AstStatement -Ast $Body.Ast -Type CommandAst | Where-Object -FilterScript { $pxTaskSpec.ContainsKey($_.GetCommandName()) } | Test-PsoxTaskDeclaration

    #parse tasks
    $allPsoxTasks = & $Body

    switch ($Mode)
    {
        'Parse'
        {
            $allPsoxTasks
            break
        }

        'Test'
        {
            Invoke-PsoxTask -Task $allPsoxTasks -Mode Test
            break
        }

        'Set'
        {
            Invoke-PsoxTask -Task $allPsoxTasks -Mode Set
            break
        }
    }
}

#region target pxWinRMTarget

    class pxWinRMTarget : pxTarget
    {
        [hashtable]$PSSessionParameters = @{}

        pxWinRMTarget([hashtable]$Parameters)
        {
            if ($Parameters.ContainsKey('PSSessionParameters'))
            {
                $this.PSSessionParameters = $Parameters['PSSessionParameters']
            }
        }
    }

$pxWinRMTargetSpec = @{
    Name   = 'pxWinRMTarget'
    Syntax = '[string|[hashtable]]'
    Target = @{
        Mandatory = $true
        Type      = [StringConstantExpressionAst], [ExpandableStringExpressionAst], [HashtableAst], [VariableExpressionAst]
    }
}

#endregion

#region task pxRole

function pxRole
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [hashtable]$Body
    )

    $roleFile = Resolve-PsoxPath -Path $Body.FilePath

    $pxExecutionContext = [pxExectuionContext]@{
        CurrentParserType = 'pxRole'
        CurrentParserName = $Name
        RootFolder        = Split-Path -Path $roleFile -Parent
    }
    
    $roleBody = (Get-Command -Name $roleFile).ScriptBlock

    #validate body
    Get-AstStatement -Ast $roleBody.Ast -Type CommandAst | Where-Object -FilterScript { $pxTaskSpec.ContainsKey($_.GetCommandName()) } | Test-PsoxTaskDeclaration

    #parse tasks
    if ($Body.ContainsKey('Parameters'))
    {
        $roleParameters = $Body['Parameters']
        & $roleBody @roleParameters
    }
    else
    {
        & $roleBody
    }
}

$pxRoleSpec = @{
    TaskName   = 'pxRole'
    Syntax     = 'pxRole <[string]Name> @{
    FilePath   = [string]
    [ Parameters = [hashtable] ]
}'
    Parameters = @{
        FilePath   = @{
            Mandatory  = $true
            Type       = [StringConstantExpressionAst]
            IsFilePath = $true
        }
        Parameters = @{
            Mandatory              = $false
            type                   = [HashtableAst], [ScriptBlockExpressionAst], [VariableExpressionAst]
            AllowRuntimeEvaluation = $true
        }
    }
}

#endregion

#region task pxScript
function pxScript
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [hashtable]$Body
    )

    [pxFatory]::CreateTask($Name, $Body, [pxScript] , [pxWinRMTarget], $pxExecutionContext)
}

class pxScript : pxTask
{
    [void]Connect()
    {
        try
        {
            $this.LogInformation('Connect', 'Started')
            if (-not [pxConnectionManager]::ConnectionExist($this.Target.ConnectionId))
            {
                $newPSSessionParams = @{
                    ComputerName = $this.Target.Endpoint
                    Name         = $this.Target.DisplayName
                } + $this.Target.PSSessionParameters
                $ses = New-PSSession @newPSSessionParams -ErrorAction Stop
                Invoke-Command -Session $ses -ScriptBlock { $ProgressPreference = 'SilentlyContinue' }
                [pxConnectionManager]::AddConnection($this.Target.ConnectionId, $ses)
                $this.LogInformation('Connect', 'Connected')
            }
            else
            {
                $this.LogInformation('Connect', 'Already connected')
            }
        }
        catch
        {
            $this.LogError('Connect', $_)
        }
    }

    [void]Prepare()
    {
        $this.LogInformation('Prepare', 'Skipped. This task does not need to prepare anything')
    }

    [void]Test()
    {
        $this.LogInformation('Test', 'Skipped. This task does not need to test anything')
    }

    [void]Set()
    {
        try
        {
            $this.LogInformation('Set', 'Started')
            #Get script content
            $scriptFilePath = Resolve-PsoxPath -Path $this.Parameters['FilePath']
            $scriptContent = Get-Content -Path $scriptFilePath -Raw

            #Create pipeline for execution
            $session = [pxConnectionManager]::GetConnection($this.Target.ConnectionId)
            $pipeline = $session.Runspace.CreatePipeline()
            $pipeline.Commands.AddScript($scriptContent)
            if ($this.Parameters.ContainsKey('Parameters'))
            {
                foreach ($parKey in $this.Parameters['Parameters'].Keys)
                {
                    $pipeline.Commands[0].Parameters.Add($parKey, $this.Parameters['Parameters'][$parKey]) 
                }
            }
            $this.Output = $pipeline.Invoke()
            $pipeline.Dispose()
            $this.State.Updated = $true
            $this.LogInformation('Set', 'Completed')
        }
        catch
        {
            $this.LogError('Set', $_)
        }
    }
}

$pxScriptSpec = @{
    TaskName   = 'pxScript'
    Syntax     = "pxScript <[string]Name> @{
    Target     = $($pxWinRMTargetSpec.Syntax)
    FilePath   = [string]
    [ Parameters = [hashtable] ]
}"
    Parameters = @{
        Target     = $pxWinRMTargetSpec.Target
        FilePath   = @{
            Mandatory  = $true
            Type       = [StringConstantExpressionAst]
            IsFilePath = $true
        }
        Parameters = @{
            Mandatory              = $false
            type                   = [HashtableAst], [ScriptBlockExpressionAst], [VariableExpressionAst]
            AllowRuntimeEvaluation = $true
        }
    }
}
#endregion

#region task pxDsc
function pxDsc
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [hashtable]$Body
    )

    [pxFatory]::CreateTask($Name, $Body, [pxDsc] , [pxWinRMTarget], $pxExecutionContext)
}

class pxDsc : pxTask
{
    [void]Connect()
    {
        try
        {
            $this.LogInformation('Connect', 'Started')
            if (-not [pxConnectionManager]::ConnectionExist($this.Target.ConnectionId))
            {
                $newPSSessionParams = @{
                    ComputerName = $this.Target.Endpoint
                    Name         = $this.Target.DisplayName
                } + $this.Target.PSSessionParameters
                $ses = New-PSSession @newPSSessionParams -ErrorAction Stop
                Invoke-Command -Session $ses -ScriptBlock { $ProgressPreference = 'SilentlyContinue' }
                [pxConnectionManager]::AddConnection($this.Target.ConnectionId, $ses)
                $this.LogInformation('Connect', 'Connected')
            }
            else
            {
                $this.LogInformation('Connect', 'Already connected')
            }
        }
        catch
        {
            $this.LogError('Connect', $_)
        }
    }

    [void]Prepare()
    {
        try
        {
            $this.LogInformation('Prepare', 'Started')
            Invoke-Command -Session ([pxConnectionManager]::GetConnection($this.Target.ConnectionId)) -ScriptBlock {
                $getDscResourceParams = @{
                    Name   = $Args[0]['Resource']
                    Module = $Args[0]['Module']
                }
                $dscResExist = Get-DscResource @getDscResourceParams -ErrorAction SilentlyContinue -Verbose:$false
                if (-not $dscResExist)
                {
                    $installModuleParams = @{
                        Force              = $true
                        SkipPublisherCheck = $true
                        #AcceptLicense      = $true
                    }
                    if ($Args[0]['Module'].Contains('/'))
                    {
                        $installModuleParams['Name'], $installModuleParams['RequiredVersion'] = $Args[0]['Module'] -split '/'
                    }
                    else
                    {
                        $installModuleParams['Name'] = $Args[0]['Module']
                    }
                    Install-Module @installModuleParams -ErrorAction Stop -Verbose:$false
                }
            } -ArgumentList $this.Parameters
            $this.LogInformation('Prepare', 'Completed')
        }
        catch
        {
            $this.LogError('Prepare', $_)
        }
    }

    [psobject]InvokeDscResource([string]$Method)
    {
        $res = Invoke-Command -Session ([pxConnectionManager]::GetConnection($this.Target.ConnectionId)) -ScriptBlock {
            $invokeDscResourceParams = @{
                Method   = $Args[1]
                Name     = $Args[0]['Resource']
                Property = $Args[0]['Properties']
                Module   = $Args[0]['Module']
            }
            Invoke-DscResource @invokeDscResourceParams -ErrorAction Stop -Verbose:$false | ConvertTo-Json -Compress
        } -ArgumentList $this.Parameters, $Method -ErrorAction Stop
        return ($res | ConvertFrom-Json)
    }

    [void]Test()
    {
        try
        {
            $this.LogInformation('Test', 'Started')
            $res = $this.InvokeDscResource('Test')
            $this.State.InDesiredState = $res.InDesiredState
            $this.State.Tested = $true
            $this.LogInformation('Test', 'Completed')
        }
        catch
        {
            $this.LogError('Test', $_)
        }
    }

    [void]Set()
    {
        try
        {
            $this.LogInformation('Set', 'Started')
            if (-not $this.State.InDesiredState)
            {
                $res = $this.InvokeDscResource('Set')
                $this.State.RebootRequired = $res.RebootRequired
                $this.State.Updated = $true
                $this.LogInformation('Set', 'Completed')

                #re-testing
                $this.LogInformation('Set', 'Restarted')
                $res = $this.InvokeDscResource('Test')
                $this.State.InDesiredState = $res.InDesiredState
                $this.LogInformation('Set', 'Completed')
            }
            else
            {
                $this.LogInformation('Set', 'Skipped, already in desired state')
            }
        }
        catch
        {
            $this.LogError('Set', $_)
        }
    }
}

$pxDscSpec = @{
    TaskName   = 'pxDsc'
    TargetType = $pxWinRMTargetSpec.Name
    Syntax     = "pxDsc <[string]Name> @{
    Target     = $($pxWinRMTargetSpec.Syntax)
    Resource   = [string]
    Module     = [string]
    Properties = [hashtable]
}"
    Parameters = @{
        Target     = $pxWinRMTargetSpec.Target
        Resource   = @{
            Mandatory = $true
            Type      = [StringConstantExpressionAst], [ExpandableStringExpressionAst], [VariableExpressionAst]
        }
        Module     = @{
            Mandatory = $true
            Type      = [StringConstantExpressionAst], [ExpandableStringExpressionAst], [VariableExpressionAst]
        }
        Properties = @{
            Mandatory              = $true
            type                   = [HashtableAst], [ScriptBlockExpressionAst], [VariableExpressionAst]
            AllowRuntimeEvaluation = $true
        }
    }
}
#endregion

$pxTaskSpec = @{
    $pxDscSpec.TaskName    = $pxDscSpec
    $pxRoleSpec.TaskName   = $pxRoleSpec
    $pxScriptSpec.TaskName = $pxScriptSpec
}