# Build script

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Release")]
    [Alias("c")]
    [System.String] $Configuration = "Debug",

    [Parameter(Mandatory=$false)]
    [Alias("v")]
    [System.String] $Version = "1.0.0",

    [Parameter(Mandatory=$false)]
    [Alias("vs")]
    [System.String] $VersionSuffix = "dev",

    [Parameter(Mandatory=$false)]
    [Alias("ff")]
    [System.Boolean] $FailFast = $true
)

#
# Variables
#
Write-Verbose "Setup environment variables."
$env:LE_ROOT_DIR = (Get-Item (Split-Path $MyInvocation.MyCommand.Path)).Parent.FullName
$env:LE_TOOLS_DIR = Join-Path $env:LE_ROOT_DIR "tools"
$env:LE_PACKAGES_DIR = Join-Path $env:LE_ROOT_DIR "packages"

#
# Dotnet configuration
#
# Disable first run since we want to control all package sources 
Write-Verbose "Setup dotnet configuration."
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = 1 
$env:NUGET_PACKAGES = $env:LE_PACKAGES_DIR
$env:DOTNET_CLI_VERSION = "latest"
$env:NUGET_EXE_Version = "3.4.3"


#
# Build configuration
#
$LEB_Solution = Join-Path $env:LE_ROOT_DIR "TestPlatform.TestLoggers.sln"
$LEB_LoggerProjects = (Join-Path $env:LE_ROOT_DIR "src\Appveyor.TestLogger\Appveyor.TestLogger.csproj"),(Join-Path $env:LE_ROOT_DIR "src\JUnit.Xml.TestLogger\JUnit.Xml.TestLogger.csproj"),(Join-Path $env:LE_ROOT_DIR "src\Xunit.Xml.TestLogger\Xunit.Xml.TestLogger.csproj")
$LEB_RestoreProject = Join-Path $env:LE_ROOT_DIR "src\ExternalPackage\Restore.csproj"
$LEB_TestProjectsDir = Join-Path $env:LE_ROOT_DIR "test"
$LEB_AppveyorNuspecProject = Join-Path $env:LE_ROOT_DIR "nuspec\Appveyor.TestLogger.nuspec"
$LEB_JunitXmlNuspecProject = Join-Path $env:LE_ROOT_DIR "nuspec\JunitXml.TestLogger.nuspec"
$LEB_XunitXmlNuspecProject = Join-Path $env:LE_ROOT_DIR "nuspec\XunitXml.TestLogger.nuspec"
$LEB_Configuration = $Configuration
$LEB_Version = $Version
$LEB_VersionSuffix = $VersionSuffix
$LEB_FullVersion = if ($VersionSuffix -ne '') {$Version + "-" + $VersionSuffix} else {$Version}

# Capture error state in any step globally to modify return code
$Script:ScriptFailed = $false


function Write-Log ([string] $message)
{
    $currentColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = "Green"
    if ($message)
    {
        Write-Output "... $message"
    }
    $Host.UI.RawUI.ForegroundColor = $currentColor
}

function Install-DotNetCli
{
    $timer = Start-Timer
    Write-Log "Install-DotNetCli: Get dotnet-install.ps1 script..."
    $dotnetInstallRemoteScript = "https://raw.githubusercontent.com/dotnet/cli/release/2.0.0/scripts/obtain/dotnet-install.ps1"
    $dotnetInstallScript = Join-Path $env:LE_TOOLS_DIR "dotnet-install.ps1"
    if (-not (Test-Path $env:LE_TOOLS_DIR)) {
        New-Item $env:LE_TOOLS_DIR -Type Directory | Out-Null
    }

    $dotnet_dir= Join-Path $env:LE_TOOLS_DIR "dotnet"

    if (-not (Test-Path $dotnet_dir)) {
        New-Item $dotnet_dir -Type Directory | Out-Null
    }

    (New-Object System.Net.WebClient).DownloadFile($dotnetInstallRemoteScript, $dotnetInstallScript)

    if (-not (Test-Path $dotnetInstallScript)) {
        Write-Error "Failed to download dotnet install script."
    }

    Unblock-File $dotnetInstallScript

    Write-Log "Install-DotNetCli: Get the latest dotnet cli toolset..."
    $dotnetInstallPath = Join-Path $env:LE_TOOLS_DIR "dotnet"
    New-Item -ItemType directory -Path $dotnetInstallPath -Force | Out-Null
    & $dotnetInstallScript -Channel "2.0" -InstallDir $dotnetInstallPath -NoPath -Version $env:DOTNET_CLI_VERSION

    # Pull in additional shared frameworks.
    # Get netcoreapp1.0 shared components.
    & $dotnetInstallScript -InstallDir $dotnetInstallPath -SharedRuntime -Version 'latest' -Channel '1.0'

    # Get netcoreapp1.1 shared components.
    & $dotnetInstallScript -InstallDir $dotnetInstallPath -SharedRuntime -Version 'latest' -Channel '1.1'

    # Get shared components which is compatible with dotnet cli version $env:DOTNET_CLI_VERSION
    & $dotnetInstallScript -InstallDir $dotnetInstallPath -SharedRuntime -Version $env:DOTNET_RUNTIME_VERSION -Channel 'master'

    Write-Log "Install-DotNetCli: Complete. {$(Get-ElapsedTime($timer))}"
}

function Restore-Package
{
    $timer = Start-Timer
    $dotnetExe = Get-DotNetPath

    Write-Log ".. .. Restore-Package: Source: $LEB_RestoreProject"
    & $dotnetExe restore $LEB_RestoreProject --packages $env:LE_PACKAGES_DIR -v:minimal -warnaserror

    if ($lastExitCode -ne 0) {
        Set-ScriptFailed
    }

    Write-Log "Restore-Package: Complete. {$(Get-ElapsedTime($timer))}"
}

function Invoke-FirstBuild
{
    $timer = Start-Timer
    Write-Log "Invoke-Build: Start build."
    $dotnetExe = Get-DotNetPath

    ForEach ($proj in $LEB_LoggerProjects) {
        Write-Log ".. .. Build: Source: $proj"
        Write-Log "$dotnetExe build $proj --configuration $LEB_Configuration -v:minimal -p:Version=$LEB_FullVersion"
        & $dotnetExe build $proj --configuration $LEB_Configuration -v:minimal -p:Version=$LEB_FullVersion
        Write-Log ".. .. Build: Complete."

        if ($lastExitCode -ne 0) {
            Set-ScriptFailed
        }
    }

    Write-Log "Invoke-Build: Complete. {$(Get-ElapsedTime($timer))}"
}

function Invoke-Build
{
    $timer = Start-Timer
    Write-Log "Invoke-Build: Start build."
    $dotnetExe = Get-DotNetPath

    Write-Log ".. .. Build: Source: $LEB_Solution"
    Write-Log "$dotnetExe build $LEB_Solution --configuration $LEB_Configuration -v:minimal -p:Version=$LEB_FullVersion"
    & $dotnetExe build $LEB_Solution --configuration $LEB_Configuration -v:minimal -p:Version=$LEB_FullVersion
    Write-Log ".. .. Build: Complete."

    if ($lastExitCode -ne 0) {
        Set-ScriptFailed
    }

    Write-Log "Invoke-Build: Complete. {$(Get-ElapsedTime($timer))}"
}

function Run-Test
{
    $timer = Start-Timer
    $dotnetExe = Get-DotNetPath

    #remove previously built packages.
    Remove-Item -Recurse -Force (Join-Path $env:LE_PACKAGES_DIR "appveyor.testlogger") -ErrorAction Ignore
    Remove-Item -Recurse -Force (Join-Path $env:LE_PACKAGES_DIR "junitxml.testlogger") -ErrorAction Ignore
    Remove-Item -Recurse -Force (Join-Path $env:LE_PACKAGES_DIR "xunitxml.testlogger") -ErrorAction Ignore

    $testProject = Join-Path $LEB_TestProjectsDir "Appveyor.TestLogger.NetCore.Tests\Appveyor.TestLogger.NetCore.Tests.csproj"
    $testAdapterPath = Join-Path $LEB_TestProjectsDir "Appveyor.TestLogger.NetCore.Tests\bin\$LEB_Configuration\netcoreapp1.0"
    Write-Log ".. .. Run-Test: Source: $testProject"
    & $dotnetExe test $testProject --test-adapter-path $testAdapterPath --configuration:$LEB_Configuration --logger:Appveyor --no-build --no-restore

    $testProject = Join-Path $LEB_TestProjectsDir "Appveyor.TestLogger.NetFull.Tests\Appveyor.TestLogger.NetFull.Tests.csproj"
    Write-Log ".. .. Run-Test: Source: $testProject"
    & $dotnetExe test $testProject --configuration:$LEB_Configuration --logger:Appveyor --no-build --no-restore
	
    $testProject = Join-Path $LEB_TestProjectsDir "Junit.Xml.TestLogger.NetCore.Tests\Junit.Xml.TestLogger.NetCore.Tests.csproj"
    $testAdapterPath = Join-Path $LEB_TestProjectsDir "Junit.Xml.TestLogger.NetCore.Tests\bin\$LEB_Configuration\netcoreapp1.0"
    $loggerFilePath = Join-Path $LEB_TestProjectsDir "Junit.Xml.TestLogger.NetCore.Tests\loggerFile.xml"
    Remove-Item $loggerFilePath -ErrorAction Ignore
    Write-Log ".. .. Run-Test: Source: $testProject"
    & $dotnetExe test $testProject --test-adapter-path $testAdapterPath --configuration:$LEB_Configuration --logger:"junit;LogFilePath=loggerFile.xml" --no-build --no-restore

    # Check junit logger is creating logger file
    if( -not(Test-Path $loggerFilePath)){
        Write-Error "File $loggerFilePath does not exist"
        Set-ScriptFailed
    }

    $testProject = Join-Path $LEB_TestProjectsDir "Junit.Xml.TestLogger.NetFull.Tests\Junit.Xml.TestLogger.NetFull.Tests.csproj"
    $loggerFilePath = Join-Path $LEB_TestProjectsDir "Junit.Xml.TestLogger.NetFull.Tests\TestResults\TestResults.xml"
    Remove-Item $loggerFilePath -ErrorAction Ignore
    Write-Log ".. .. Run-Test: Source: $testProject"
    & $dotnetExe test $testProject --configuration:$LEB_Configuration --logger:junit --no-build --no-restore

    # Check junit logger is creating logger file
    if( -not(Test-Path $loggerFilePath)){
        Write-Error "File $loggerFilePath does not exist"
        Set-ScriptFailed
    }
	
    $testProject = Join-Path $LEB_TestProjectsDir "Xunit.Xml.TestLogger.NetCore.Tests\Xunit.Xml.TestLogger.NetCore.Tests.csproj"
    $testAdapterPath = Join-Path $LEB_TestProjectsDir "Xunit.Xml.TestLogger.NetCore.Tests\bin\$LEB_Configuration\netcoreapp1.0"
    $loggerFilePath = Join-Path $LEB_TestProjectsDir "Xunit.Xml.TestLogger.NetCore.Tests\loggerFile.xml"
    Remove-Item $loggerFilePath -ErrorAction Ignore
    Write-Log ".. .. Run-Test: Source: $testProject"
    & $dotnetExe test $testProject --test-adapter-path $testAdapterPath --configuration:$LEB_Configuration --logger:"xunit;LogFilePath=loggerFile.xml" --no-build --no-restore

    # Check xunit logger is creating logger file
    if( -not(Test-Path $loggerFilePath)){
        Write-Error "File $loggerFilePath does not exist"
        Set-ScriptFailed
    }

    $testProject = Join-Path $LEB_TestProjectsDir "Xunit.Xml.TestLogger.NetFull.Tests\Xunit.Xml.TestLogger.NetFull.Tests.csproj"
    $loggerFilePath = Join-Path $LEB_TestProjectsDir "Xunit.Xml.TestLogger.NetFull.Tests\TestResults\TestResults.xml"
    Remove-Item $loggerFilePath -ErrorAction Ignore
    Write-Log ".. .. Run-Test: Source: $testProject"
    & $dotnetExe test $testProject --configuration:$LEB_Configuration --logger:xunit --no-build --no-restore

    # Check xunit logger is creating logger file
    if( -not(Test-Path $loggerFilePath)){
        Write-Error "File $loggerFilePath does not exist"
        Set-ScriptFailed
    }

    Write-Log "Run-Test: Complete. {$(Get-ElapsedTime($timer))}"
}

function Create-NugetPackages
{
    $timer = Start-Timer
    $dotnetExe = Get-DotNetPath

    Write-Log "Create-NugetPackages: Started."
    $lePackageDirectory = Join-Path $env:LE_ROOT_DIR "nugetPackage"
    New-Item -ItemType directory -Path $lePackageDirectory -Force | Out-Null

    # Copy Appveyor, junit xml, and xunit xml logger dll in Nuspec folder
    $sourceFile = Join-Path $env:LE_ROOT_DIR "src\Appveyor.TestLogger\bin\$LEB_Configuration\netstandard1.5\Microsoft.VisualStudio.TestPlatform.Extension.Appveyor.TestLogger.dll"
    Copy-Item $sourceFile $lePackageDirectory -Force

    $sourceFile = Join-Path $env:LE_ROOT_DIR "src\Junit.Xml.TestLogger\bin\$LEB_Configuration\netstandard1.5\Microsoft.VisualStudio.TestPlatform.Extension.Junit.Xml.TestLogger.dll"
    Copy-Item $sourceFile $lePackageDirectory -Force

    $sourceFile = Join-Path $env:LE_ROOT_DIR "src\Xunit.Xml.TestLogger\bin\$LEB_Configuration\netstandard1.5\Microsoft.VisualStudio.TestPlatform.Extension.Xunit.Xml.TestLogger.dll"
    Copy-Item $sourceFile $lePackageDirectory -Force

    $nugetExe = Join-Path $env:LE_PACKAGES_DIR -ChildPath "Nuget.CommandLine" | Join-Path -ChildPath $env:NUGET_EXE_Version | Join-Path -ChildPath "tools\NuGet.exe"

    # Call nuget pack on these components.
    Write-Log ".. .. Create-NugetPackages: $nugetExe pack $LEB_AppveyorNuspecProject -OutputDirectory $lePackageDirectory -Version $LEB_FullVersion -Properties Version=$LEB_FullVersion"
    & $nugetExe pack $LEB_AppveyorNuspecProject -OutputDirectory $lePackageDirectory -Version $LEB_FullVersion -Properties Version=$LEB_FullVersion

    Write-Log ".. .. Create-NugetPackages: $nugetExe pack $LEB_JunitXmlNuspecProject -OutputDirectory $lePackageDirectory -Version $LEB_FullVersion -Properties Version=$LEB_FullVersion"
    & $nugetExe pack $LEB_JunitXmlNuspecProject -OutputDirectory $lePackageDirectory -Version $LEB_FullVersion -Properties Version=$LEB_FullVersion

    Write-Log ".. .. Create-NugetPackages: $nugetExe pack $LEB_XunitXmlNuspecProject -OutputDirectory $lePackageDirectory -Version $LEB_FullVersion -Properties Version=$LEB_FullVersion"
    & $nugetExe pack $LEB_XunitXmlNuspecProject -OutputDirectory $lePackageDirectory -Version $LEB_FullVersion -Properties Version=$LEB_FullVersion

    Write-Log "Create-NugetPackages: Complete. {$(Get-ElapsedTime($timer))}"
}


#
# Helper functions
#
function Get-DotNetPath
{
    $dotnetPath = Join-Path $env:LE_TOOLS_DIR "dotnet\dotnet.exe"
    if (-not (Test-Path $dotnetPath)) {
        Write-Error "Dotnet.exe not found at $dotnetPath. Did the dotnet cli installation succeed?"
    }

    return $dotnetPath
}

function Start-Timer
{
    return [System.Diagnostics.Stopwatch]::StartNew()
}

function Get-ElapsedTime([System.Diagnostics.Stopwatch] $timer)
{
    $timer.Stop()
    return $timer.Elapsed
}

function Set-ScriptFailed
{
    if ($FailFast -eq $true) {
        Write-Error "Build failed. Stopping as fail fast is set."
    }

    $Script:ScriptFailed = $true
}

function Edit-XmlNodes {
param (
    [xml] $doc = $(throw "doc is a required parameter"),
    [string] $xpath = $(throw "xpath is a required parameter"),
    [string] $value = $(throw "value is a required parameter"),
    [bool] $condition = $true
)    
    if ($condition -eq $true) {
        $nodes = $doc.SelectNodes($xpath)
         
        foreach ($node in $nodes) {
            if ($node -ne $null) {
                if ($node.NodeType -eq "Element") {
                    $node.InnerXml = $value
                }
                else {
                    $node.Value = $value
                }
            }
        }
    }
}

function Patch-TestProject {
param (
    [string]$filename = $(throw "filename is a required parameter"),
    [string]$loggername = $(throw "loggername is a required parameter"),
    [string]$version = $(throw "version is a required parameter")
)
    $xml = [xml](Get-Content $filename)
    # <file><foo attribute="bar" attribute2="bar" attribute3="bar" /></file>

    Edit-XmlNodes $xml -xpath "/Project/ItemGroup[0]/PackageReference[@Include='$loggername']/@Version" -value $version

    $xml.save($filename)
}


# Execute build
$timer = Start-Timer
New-Item -ItemType directory -Path (Join-Path $env:LE_ROOT_DIR "nugetPackage") -ErrorAction Ignore 
Write-Log "Build started: args = '$args'"
Write-Log "Test platform environment variables: "
Get-ChildItem env: | Where-Object -FilterScript { $_.Name.StartsWith("LE_") } | Format-Table
Write-Log "Test platform build variables: "
Get-Variable | Where-Object -FilterScript { $_.Name.StartsWith("LEB_") } | Format-Table
Install-DotNetCli
Restore-Package
Invoke-FirstBuild
Create-NugetPackages
Invoke-Build
Run-Test
Write-Log "Build complete. {$(Get-ElapsedTime($timer))}"
if ($Script:ScriptFailed) { Exit 1 } else { Exit 0 }
