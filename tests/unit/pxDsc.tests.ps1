$repoRootFolder = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
$moduleFolder = Join-Path -Path $repoRootFolder -ChildPath 'src' -AdditionalChildPath 'psox'
Import-Module -Name $moduleFolder -Force -ErrorAction Stop

Describe 'pxDsc' {
    It "Should parse successfully" {
        $t_result = pxScenario 'UnitTest' {
            pxDsc "Task1" @{
                Target     = 'Target01'
                Resource   = "Environment"
                Module     = 'PSDscResources'
                Properties = @{
                    Name   = 'pxTestVar01Name'
                    Value  = 'pxTestVar01Value'
                    Ensure = 'present'
                    Target = [string[]]'Process'
                }
            }
        } -Mode Parse

        $t_result.GetType().Name | Should -BeExactly 'pxDsc'
    }
    It "Should fail parsing when there is no 'Target' specified" {
        { $t_result = pxScenario 'UnitTest' {
                pxDsc "Task1" @{
                    Resource   = "Environment"
                    Module     = 'PSDscResources'
                    Properties = @{
                        Name   = 'pxTestVar01Name'
                        Value  = 'pxTestVar01Value'
                        Ensure = 'present'
                        Target = [string[]]'Process'
                    }
                }
            } -Mode Parse } | Should -Throw '*Missing mandatory task parameter: ''Target''*'
        $t_result | Should -BeNullOrEmpty
    }
    It "Should fail parsing when there is no 'Resource' specified" {
        { $t_result = pxScenario 'UnitTest' {
                pxDsc "Task1" @{
                    Target     = 'Target01'
                    Module     = 'PSDscResources'
                    Properties = @{
                        Name   = 'pxTestVar01Name'
                        Value  = 'pxTestVar01Value'
                        Ensure = 'present'
                        Target = [string[]]'Process'
                    }
                }
            } -Mode Parse } | Should -Throw '*Missing mandatory task parameter: ''Resource''*'
        $t_result | Should -BeNullOrEmpty
    }
    It "Should fail parsing when there is no 'Module' specified" {
        { $t_result = pxScenario 'UnitTest' {
                pxDsc "Task1" @{
                    Target     = 'Target01'
                    Resource   = "Environment"
                    Properties = @{
                        Name   = 'pxTestVar01Name'
                        Value  = 'pxTestVar01Value'
                        Ensure = 'present'
                        Target = [string[]]'Process'
                    }
                }
            } -Mode Parse } | Should -Throw '*Missing mandatory task parameter: ''Module''*'
        $t_result | Should -BeNullOrEmpty
    }
    It "Should fail parsing when there is no 'Properties' specified" {
        { $t_result = pxScenario 'UnitTest' {
                pxDsc "Task1" @{
                    Target   = 'Target01'
                    Resource = "Environment"
                    Module   = 'PSDscResources'
                }
            } -Mode Parse } | Should -Throw '*Missing mandatory task parameter: ''Properties''*'
        $t_result | Should -BeNullOrEmpty
    }
}