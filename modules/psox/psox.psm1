using namespace System.Management.Automation
using namespace System.Management.Automation.Language

class psoxTarget
{
    [string]$DisplayName
    [string]$Name
    [string]$Endpoint
    [string]$ConnectionId

    psoxTarget([hashtable]$Parameters)
    {
        $this.Name = $Parameters['Name']
        if ($Parameters.ContainsKey('Endpoint'))
        {
            $this.Endpoint = $Parameters['Endpoint']
            $this.DisplayName = "$($Parameters['Name'])/$($Parameters['Endpoint'])"
        }
        else
        {
            $this.Endpoint = $Parameters['Name']
            $this.DisplayName = $Parameters['Name']
        }

        $this.InitializeConnectionId()
    }
    psoxTarget([string]$Name)
    {
        $this.Name = $Name
        $this.Endpoint = $Name
        $this.DisplayName = $Name

        $this.InitializeConnectionId()
    }

    [void]InitializeConnectionId()
    {
        #calculate ConnectionId
        $connectionParamString = $this.psobject.Properties.Where( { $_.Name -notin 'Name', 'Endpoint', 'DisplayName', 'connectionId' }) | Select-Object -Property Name, Value | ConvertTo-Json -Compress -Depth 2
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

class psoxTaskState
{
    [bool]$InDesiredState
    [bool]$RebootRequired
    [string]$State = 'Unknown'

    [string]ToString()
    {
        $result = $this.State
        $resultDetails = [System.Collections.Generic.List[string]]::new()
        if ($this.RebootRequired)
        {
            $resultDetails.Add('RebootRequired')
        }
        if (-not $this.InDesiredState)
        {
            $resultDetails.Add('NotInDesiredState')
        }
        if ($resultDetails.Count -gt 0)
        {
            $result += " ($($resultDetails -join ', '))"
        }
        return $result
    }
}

enum psoxTaskStateString
{
    Parsed
    Connected
    Initialized
    Tested
    Changed
}

class psoxEvent
{
    psoxEvent([string]$Action, [string]$Type, [string]$Data)
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

class psoxTask
{
    [string]$Name
    [psoxTarget]$Target
    hidden [hashtable]$Parameters
    hidden [psobject]$Output
    hidden [System.Collections.Generic.List[psoxEvent]]$Log = [System.Collections.Generic.List[psoxEvent]]::New()
    [psoxTaskState]$State = [psoxTaskState]::new()

    psoxTask ([string]$Name, [hashtable]$Parameters, [type]$TargetType)
    {
        $this.Name = $Name
        $this.Target = $TargetType::new($Parameters.Target)
        $Parameters.Remove('Target')
        $this.Parameters = $Parameters
    }

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
        $this.Log.Add([psoxEvent]::new($Action, 'Error', $Data))
        throw "$($this.Name)::$($this.Target) - $Action - Error - $Data"
    }

    [void]LogInformation([string]$Action, [string]$Data)
    {
        $this.Log.Add([psoxEvent]::new($Action, 'Information', $Data))
        Write-Information -MessageData "$($this.Name)::$($this.Target) - $Action - $Data"
    }
}

class psoxConnectionManager
{
    static [bool]ConnectionExist([string]$Id)
    {
        return [psoxConnectionManager]::ConnectionCache.ContainsKey($Id)
    }

    static [void]AddConnection([string]$Id, [psobject]$Connection)
    {
        [psoxConnectionManager]::ConnectionCache[$Id] = $Connection
    }

    static [psobject]GetConnection([string]$Id)
    {
        if ([psoxConnectionManager]::ConnectionExist($Id))
        {
            return [psoxConnectionManager]::ConnectionCache[$Id]
        }
        else
        {
            throw "Connection: '$Id' not found"
        }
    }

    static [hashtable]$ConnectionCache = @{}
}

function Invoke-PsoxTask
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [psoxTask[]]$Task,

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
            foreach ($p in $t.Parameters.Keys)
            {
                if (($t.Parameters[$p] -is [scriptblock]) -and $taskSpec.Parameters[$p].AllowRuntimeEvaluation)
                {
                    $task.Parameters[$p] = $task.Parameters[$p].InvokeWithContext($null, [psvariable]::new('allPxTasks', $Task))
                }
            }

            #Invoke Initialize
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
                $parseErrors.Add([ParseError]::new($ta.Extent, 1, "Missing or invalid task name.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
            }
            if ($ta.CommandElements[2].GetType() -ne [HashtableAst])
            {
                $parseErrors.Add([ParseError]::new($ta.Extent, 1, "Missing task parameters.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
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
                        $parseErrors.Add([ParseError]::new($kvp.Item2.Extent, 1, "Invalid task parameter construct: '$($kvpPureExp.GetType().Name)'.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
                    }
                }
                else
                {
                    $parseErrors.Add([ParseError]::new($kvp.Item1.Extent, 1, "Invalid task parameter name: '$($kvp.Item1.Value)'.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
                }
                #mark that mandatory parameter is being used
                if ($taskSpec.Parameters[$kvp.Item1.Value].Mandatory)
                {
                    $null = $mandatoryParamsReq.Remove($kvp.Item1.Value)
                }
            }
            if ($mandatoryParamsReq.Count -gt 0)
            {
                $parseErrors.Add([ParseError]::new($ta.CommandElements[2].Extent, 1, "Missing mandatory task parameter: '$($mandatoryParamsReq -join ''', ''')'.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
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

    [psoxDsc]::new($Name, $Body, [psoxDscTarget])
}

class psoxDsc : psoxTask
{
    [psoxDscTarget]$Target

    psoxDsc([string]$Name, [hashtable]$Parameters, [type]$TargetType) : base([string]$Name, [hashtable]$Parameters, [type]$TargetType)
    {
    }

    [void]Connect()
    {
        try
        {
            $this.LogInformation('Connect', 'Started')
            if (-not [psoxConnectionManager]::ConnectionExist($this.Target.ConnectionId))
            {
                $newPSSessionParams = @{
                    ComputerName = $this.Target.Endpoint
                    Name         = $this.Target.DisplayName
                } + $this.Target.PSSessionParameters
                $ses = New-PSSession @newPSSessionParams -ErrorAction Stop
                Invoke-Command -Session $ses -ScriptBlock { $ProgressPreference = 'SilentlyContinue' }
                [psoxConnectionManager]::AddConnection($this.Target.ConnectionId, $ses)
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
            Invoke-Command -Session ([psoxConnectionManager]::GetConnection($this.Target.ConnectionId)) -ScriptBlock {
                $getDscResourceParams = @{
                    Name   = $Args[0]['Resource']
                    Module = $Args[0]['Module']
                }
                $dscResExist = Get-DscResource @getDscResourceParams -ErrorAction SilentlyContinue -Verbose:$false
                if (-not $dscResExist)
                {
                    $installModuleParams = @{
                        Force = $true
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
            $this.State.State = 'Prepared'
        }
        catch
        {
            $this.LogError('Prepare', $_)
        }
    }

    [psobject]InvokeDscResource([string]$Method)
    {
        $res = Invoke-Command -Session ([psoxConnectionManager]::GetConnection($this.Target.ConnectionId)) -ScriptBlock {
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
            $this.LogInformation('Test', 'Completed')
            $this.State.State = 'Tested'
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
                $this.LogInformation('Set', 'Completed')
                $this.State.State = 'Changed'

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


class psoxDscTarget : psoxTarget
{
    [hashtable]$PSSessionParameters = @{}

    psoxDscTarget([hashtable]$Parameters) : base([hashtable]$Parameters)
    {
        if ($Parameters.ContainsKey('PSSessionParameters'))
        {
            $this.PSSessionParameters = $Parameters['PSSessionParameters']
        }
    }
    psoxDscTarget([string]$Name) : base([string]$Name)
    {
    }
}

$pxDscSpec = @{
    TaskName   = 'pxDsc'
    Syntax     = 'pxDsc <[string]Name> @{
        Target     = [string|hashtable]
        Resource   = [string]
        Module     = [string]
        Properties = [hashtable]
    }'
    Parameters = @{
        Target     = @{
            Mandatory = $true
            Type      = [StringConstantExpressionAst], [ExpandableStringExpressionAst], [HashtableAst]
        }
        Resource   = @{
            Mandatory = $true
            Type      = [StringConstantExpressionAst], [ExpandableStringExpressionAst]
        }
        Module     = @{
            Mandatory = $true
            Type      = [StringConstantExpressionAst], [ExpandableStringExpressionAst]
        }
        Properties = @{
            Mandatory              = $true
            type                   = [HashtableAst], [ScriptBlockExpressionAst], [ScriptBlockExpressionAst]
            AllowRuntimeEvaluation = $true
        }
    }
}
#endregion

$pxTaskSpec = @{
    $pxDscSpec.TaskName = $pxDscSpec
}