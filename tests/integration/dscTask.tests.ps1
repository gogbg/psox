$repoRootFolder = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
$modulesFolder = Join-Path -Path $repoRootFolder -ChildPath 'src'
$pathSeperator = [System.IO.Path]::PathSeparator
if ($modulesFolder -notin ($env:PSModulePath -split $pathSeperator))
{
    Write-Verbose -Message 'Prepending modulesFolder directory to $env:PSModulePath'
    $env:PSModulePath = $modulesFolder, $env:PSModulePath -join $pathSeperator
}
Import-Module -Name psox

pxScenario blq {
    $Target = @{
        Name                = ''
        PSSessionParameters = @{
            Authentication = 'Negotiate'
            Credential     = ''
            UseSSL         = $true
            Port           = 5986
            SessionOption  = New-PSSessionOption -SkipCACheck -SkipCNCheck
        }
    }

    pxDsc "Task1" @{
        Target     = @{
            Name                = '20.46.120.31'
            PSSessionParameters = $sesParam
        }
        Resource   = "Environment"
        Module     = 'PSDscResources'
        Properties = @{
            Name   = 'pxTestVar01Name'
            Value  = 'pxTestVar01Value3'
            Ensure = 'present'
            Target = [string[]]'Process'
        }
    }
    pxDsc "Download Software" @{
        Target     = $Target
        Resource   = "xRemoteFile"
        Module     = 'xPSDesiredStateConfiguration'
        Properties = @{
            DestinationPath = 'c:\bin\7zip.msi'
            Uri             = 'https://www.7-zip.org/a/7z1900-x64.msi'
        }
    }
    pxDsc "Install Software" @{
        Target     = $Target
        Resource   = "MsiPackage"
        Module     = 'PSDscResources'
        Properties = @{
            Path      = 'c:\bin\7zip.msi'
            ProductId = '23170F69-40C1-2702-1900-000001000000'
            Ensure    = 'Present'
        }
    }
} -OutVariable pxVar -Mode Test -InformationAction Continue