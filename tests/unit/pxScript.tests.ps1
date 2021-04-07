$repoRootFolder = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
$moduleFolder = Join-Path -Path $repoRootFolder -ChildPath 'src' -AdditionalChildPath 'psox'
Import-Module -Name $moduleFolder -Force -ErrorAction Stop

Describe 'pxScript' {

    It "Should parse successfully when no Parameters are specified" {
        $t_result = pxScenario 'UnitTest' {
            pxScript "Task1" @{
                Target   = 'Target01'
                FilePath = 'testresources/script01.ps1'
            }
        } -Mode Parse

        $t_result.GetType().Name | Should -BeExactly 'pxScript'
    }
    It "Should parse successfully when Parameters are specified" {
        $t_result = pxScenario 'UnitTest' {
            pxScript "Task1" @{
                Target     = 'Target01'
                FilePath   = 'testresources/script01.ps1'
                Parameters = @{
                    Param1 = '01'
                }
            }
        } -Mode Parse

        $t_result.GetType().Name | Should -BeExactly 'pxScript'
    }
    It "Should fail parsing when there is no 'Target' specified" {
        { $t_result = pxScenario 'UnitTest' {
                pxScript "Task1" @{
                    FilePath   = 'testresources/script01.ps1'
                    Parameters = @{
                        Param1 = '01'
                    }
                }
            } -Mode Parse } | Should -Throw '*Missing mandatory task parameter: ''Target''*'
        $t_result | Should -BeNullOrEmpty
    }
}