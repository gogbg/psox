$repoRootFolder = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
$moduleFolder = Join-Path -Path $repoRootFolder -ChildPath 'src' -AdditionalChildPath 'psox'
Import-Module -Name $moduleFolder -Force -ErrorAction Stop

Describe 'pxScenario' {

}