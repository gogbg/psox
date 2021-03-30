[cmdletbinding()]
param
(
    [Parameter(Mandatory)]
    [string]$Param1,

    [Parameter()]
    [string]$Param2
)

$PSBoundParameters | ConvertTo-Json