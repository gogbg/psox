param
(
    [parameter(Mandatory)]
    [string]$Param1,

    [Parameter(Mandatory)]
    [hashtable]$Target
)
pxScript "Alteryx-contoller-Task1" @{
    Target     = $Target
    FilePath   = 'script01.ps1'
    Parameters = @{
        Param1 = 'SomeTestValue1231'
    }
}
pxDsc "Alteryx-contoller-Task2" @{
    Target     = $Target
    Resource   = "xRegistry"
    Module     = 'xPSDesiredStateConfiguration'
    Properties = { @{
            Key       = 'HKLM:\SOFTWARE'
            ValueName = 'Prop1'
            ValueData = $allPxTasks.Where( { $_.Name.Name -eq 'Alteryx-contoller-Task1' }).Output
            Ensure    = 'present'
            ValueType = 'String'
        }
    }
}
