$repoRootFolder = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
$modulesFolder = Join-Path -Path $repoRootFolder -ChildPath 'modules'
$pathSeperator = [System.IO.Path]::PathSeparator
if ($modulesFolder -notin ($env:PSModulePath -split $pathSeperator))
{
    Write-Verbose -Message 'Prepending modulesFolder directory to $env:PSModulePath'
    $env:PSModulePath = $modulesFolder, $env:PSModulePath -join $pathSeperator
}
Import-Module -Name psox -Force

pxScenario blq {
    foreach ($i in 1,2,3)
    {
        pxDsc "Test" @{
            Resource   = "Feature$i"
            Properties = @{}
        }
    }
    pxDsc alabala @{
        Resource   = 'WindowsFeature'
        Properties = @{

        }
    }
}
