# $repoRootFolder = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
# $modulesFolder = Join-Path -Path $repoRootFolder -ChildPath 'src'
# $pathSeperator = [System.IO.Path]::PathSeparator
# if ($modulesFolder -notin ($env:PSModulePath -split $pathSeperator))
# {
#     Write-Verbose -Message 'Prepending modulesFolder directory to $env:PSModulePath'
#     $env:PSModulePath = $modulesFolder, $env:PSModulePath -join $pathSeperator
# }
# Import-Module -Name psox -Force

pxScenario MyScenario {
    $Target = @{
        Name                = 'vm1'
        PSSessionParameters = @{
            Authentication    = 'Negotiate'
            Credential        = [pscredential]::new('aa', ('bb' | ConvertTo-SecureString -AsPlainText))
            UseSSL            = $true
            Port              = 5986
            ConfigurationName = 'PowerShell.7'
            SessionOption     = New-PSSessionOption -SkipCACheck -SkipCNCheck
        }
    }

    pxRole 'Windows Server' @{
        FilePath   = "pxRole-WS2019.ps1"
        Parameters = @{
            Target = $Target
        }
    }



} -OutVariable pxVar -Mode parse -InformationAction Continue
