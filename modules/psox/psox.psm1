class psoxTaskResult
{
    [bool]$RebootRequired
    [psobject]$Output
}

class psoxTask
{
    [string]$Name
    [hashtable]$Parameters
    [psoxTaskResult]$result
    [timespan]$ExecutionTime
    [psoxTaskState]$State = [psoxTaskState]::Initialized
}

class pxDsc : psoxTask
{
    
}

enum psoxTaskState
{
    Initialized
}

function New-PsoxKeyword
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [Management.Automation.Language.DynamicKeywordNameMode]$NameMode = [Management.Automation.Language.DynamicKeywordNameMode]::SimpleNameRequired,

        [Parameter(Mandatory)]
        [Management.Automation.Language.DynamicKeywordBodyMode]$BodyMode,

        [Parameter()]
        [scriptblock[]]$SemanticCheck,

        [Parameter()]
        [System.Management.Automation.Language.DynamicKeywordProperty[]]$Property
    )

    $psoxKW = [System.Management.Automation.Language.DynamicKeyword]::new()
    $psoxKW.Keyword = $Name
    $psoxKW.NameMode = $NameMode
    $psoxKW.BodyMode = $BodyMode
    if ($PSBoundParameters.ContainsKey('SemanticCheck'))
    {
        foreach ($sc in $SemanticCheck)
        {
            $psoxKW.SemanticCheck.Add($sc)
        }
    }
    if ($PSBoundParameters.ContainsKey('Property'))
    {
        foreach ($p in $Property)
        {
            $psoxKW.Properties.Add($p.Name, $p)
        }
    }
    [System.Management.Automation.Language.DynamicKeyword]::AddKeyword($psoxKW)
}

#Discover psox tasks
function Get-PsoxModule
{
    [CmdletBinding()]
    param
    (
        [switch]$Refresh
    )

    if ([datetime]::Now - [psoxModuleCache]::Timestamp -gt [psoxModuleCache]::ExpiryPeriod -or $Refresh.IsPresent)
    {
        [psoxModuleCache]::Cache.Clear()
        Get-Module -Name 'px*' -ListAvailable | ForEach-Object -Process {
            if ($_.PrivateData.ContainsKey('PsoxData'))
            {
                $curMod = [psoxModule]@{
                    Name    = $_.Name
                    Version = $_.Version
                    Tasks   = $_.PrivateData.PsoxData.Tasks
                }
                [psoxModuleCache]::Cache.Add($curMod)
            }
        }
        [psoxModuleCache]::Timestamp = [datetime]::Now
    }

    #return
    [psoxModuleCache]::Cache
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
        $parseErrors = [System.Collections.Generic.List[System.Management.Automation.Language.ParseError]]::new()
    }
    
    process
    {
        foreach ($ta in $TaskAst)
        {
            $taskSpec = $pxTaskSpec[$ta.GetCommandName()]

            #Valridate Syntax
            if (
                ($ta.CommandElements[1].StaticType -ne [string]) -and
                ([string] -isnot $ta.CommandElements[1].StaticType)
            )
            {
                $parseErrors.Add([System.Management.Automation.Language.ParseError]::new($ta.Extent, 1, "Missing or invalid task name.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
            }
            if (
                ($ta.CommandElements[2].StaticType -ne [hashtable]) -and 
                ([hashtable] -isnot $ta.CommandElements[2].StaticType)
            )
            {
                $parseErrors.Add([System.Management.Automation.Language.ParseError]::new($ta.Extent, 1, "Missing task parameters.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
                throw [System.Management.Automation.ParseException]::new($er)
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
                if ($taskSpec.Parameters.ContainsKey($kvp.Item1.Value))
                {
                    if (
                        ($kvp.Item2.GetPureExpression().StaticType -ne $taskSpec.Parameters[$kvp.Item1.Value].Type) -and 
                        ($taskSpec.Parameters[$kvp.Item1.Value].Type -isnot $kvp.Item2.GetPureExpression().StaticType)
                    )
                    {
                        $parseErrors.Add([System.Management.Automation.Language.ParseError]::new($kvp.Item2.Extent, 1, "Invalid task parameter value type: '$($kvp.Item2.GetPureExpression().StaticType)'.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
                    }
                }
                else
                {
                    $parseErrors.Add([System.Management.Automation.Language.ParseError]::new($kvp.Item1.Extent, 1, "Invalid task parameter name: '$($kvp.Item1.Value)'.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
                }
                if ($taskSpec.Parameters[$kvp.Item1.Value].Mandatory)
                {
                    $null = $mandatoryParamsReq.Remove($kvp.Item1.Value)
                }
            }
            if ($mandatoryParamsReq.Count -gt 0)
            {
                $parseErrors.Add([System.Management.Automation.Language.ParseError]::new($ta.CommandElements[2].Extent, 1, "Missing mandatory task parameter: '$($mandatoryParamsReq -join ''', ''')'.$([System.Environment]::NewLine)Syntax: $($taskSpec.Syntax)"))
            }
        }
    }
    end
    {
        if ($parseErrors.Count -gt 0)
        {
            throw [System.Management.Automation.ParseException]::new($parseErrors)
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
        [scriptblock]$Body
    )

    Get-AstStatement -Ast $Body.Ast -Type CommandAst | Where-Object -FilterScript { $pxTaskSpec.ContainsKey($_.GetCommandName()) } | Test-PsoxTaskDeclaration

    & $Body
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

    [pxDsc]@{
        Name       = $Name
        Parameters = $Body
    }
}

$pxDscSpec = @{
    TaskName   = 'pxDsc'
    Syntax     = 'pxDsc <[string]Name> @{
        Resource   = [string]
        [ Module   = [string] ]
        Properties = [hashtable]
    }'
    Parameters = @{
        Resource   = @{
            Mandatory = $true
            Type      = [string]
        }
        Module     = @{
            Mandatory = $false
            Type      = [string]
        }
        Properties = @{
            Mandatory = $true
            type      = [hashtable]
        }
    }
}
#endregion

$pxTaskSpec = @{
    $pxDscSpec.TaskName = $pxDscSpec
}