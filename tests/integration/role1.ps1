param
(
    [parameter(Mandatory)]
    [string]$Param1,

    [Parameter(Mandatory)]
    [hashtable]$Target
)
pxScript "Task5" @{
    Target     = $Target
    FilePath   = 'script01.ps1'
    Parameters = @{
        Param1 = 'SomeTestValue1231'
    }
}
pxDsc "Task6" @{
    Target     = $Target
    Resource   = "xRegistry"
    Module     = 'xPSDesiredStateConfiguration'
    Properties = { @{
            Key       = 'HKLM:\SOFTWARE'
            ValueName = 'Prop1'
            ValueData = $allPxTasks.Where( { $_.Name.Name -eq 'Task5' }).Output
            Ensure    = 'present'
            ValueType = 'String'
        }
    }
}
