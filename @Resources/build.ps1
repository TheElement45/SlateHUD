# Compile before stopping the daemon. A failed build leaves the installed helper intact.
param([switch]$RestartHelper, [switch]$SkipPlugin)
$ErrorActionPreference = 'Stop'
$here = [IO.Path]::GetFullPath($PSScriptRoot)
$helperPath = Join-Path $here 'SlateHUDHelper.exe'
$stagedPath = Join-Path $here ('SlateHUDHelper.' + [Guid]::NewGuid().ToString('N') + '.tmp')
$fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$winmd = Join-Path $env:WINDIR 'System32\WinMetadata'
$restart = $false
try {
    & "$fw\csc.exe" /nologo /target:exe /platform:anycpu /optimize+ `
        "/out:$stagedPath" "/r:$fw\System.Runtime.WindowsRuntime.dll" "/r:$fw\System.Runtime.dll" `
        "/r:$fw\System.Runtime.InteropServices.WindowsRuntime.dll" `
        "/r:$fw\System.Management.dll" `
        "/r:$fw\System.Web.Extensions.dll" `
        "/r:$winmd\Windows.Foundation.winmd" "/r:$winmd\Windows.Media.winmd" "/r:$winmd\Windows.Storage.winmd" `
        (Join-Path $here 'SlateHUDHelper.cs') (Join-Path $here 'MediaHelper.cs') `
        (Join-Path $here 'ArtworkHelper.cs') (Join-Path $here 'TelemetryHelper.cs') `
        (Join-Path $here 'DisplayProbe.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Helper compilation failed; previous binary retained.' }
    if ($RestartHelper) {
        $owned = @(Get-Process -Name SlateHUDHelper -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.Equals($helperPath, [StringComparison]::OrdinalIgnoreCase)
        })
        foreach ($process in $owned) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
            $restart = $true
        }
    }
    if ([IO.File]::Exists($helperPath)) {
        [IO.File]::Replace($stagedPath, $helperPath, [NullString]::Value)
    } else {
        [IO.File]::Move($stagedPath, $helperPath)
    }
    Write-Output "Built $helperPath"
}
finally {
    if ([IO.Path]::GetDirectoryName($stagedPath).Equals($here, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $stagedPath -PathType Leaf)) { Remove-Item -LiteralPath $stagedPath -Force }
    Get-ChildItem -LiteralPath $here -Filter 'SlateHUDHelper.exe~RF*.TMP' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

# Build native x64 Rainmeter plugin (SlateHUD.dll) when Visual Studio C++ tools are present.
$pluginSrc = Join-Path $here 'Plugin\SlateHUD.cpp'
if ($SkipPlugin) {
    Write-Output 'Skipped native SlateHUD.dll build (-SkipPlugin).'
} elseif (Test-Path -LiteralPath $pluginSrc -PathType Leaf) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsPath = ''
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    }
    $vcvars = if ($vsPath) { Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat' } else { '' }
    if (-not $vcvars -or -not (Test-Path -LiteralPath $vcvars -PathType Leaf)) {
        throw 'MSVC x64 Build Tools (vcvars64.bat) not found; cannot build SlateHUD.dll (pass -SkipPlugin to build only SlateHUDHelper.exe).'
    }

    $pluginsDir = Join-Path $here 'Plugins'
    [void][IO.Directory]::CreateDirectory($pluginsDir)
    $dllPath = Join-Path $pluginsDir 'SlateHUD.dll'
    $stagedDll = Join-Path $pluginsDir ('SlateHUD.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $buildTmp = Join-Path $here ('.tmp-plugin-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($buildTmp)
    try {
        $cmdScript = Join-Path $buildTmp 'build.cmd'
        $objPath = Join-Path $buildTmp 'SlateHUD.obj'
        $impPath = Join-Path $buildTmp 'SlateHUD.lib'
        $cmdBody = @(
            '@echo off',
            "call `"$vcvars`" >nul || exit /b 1",
            "cl.exe /nologo /LD /O2 /EHsc /MT /std:c++17 /DUNICODE /D_UNICODE `"/Fo$objPath`" `"/Fe$stagedDll`" `"$pluginSrc`" /link user32.lib advapi32.lib `"/IMPLIB:$impPath`""
        ) -join "`r`n"
        [IO.File]::WriteAllText($cmdScript, $cmdBody, [Text.Encoding]::ASCII)
        & $env:ComSpec /d /c $cmdScript
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stagedDll -PathType Leaf)) {
            throw 'Native SlateHUD.dll compilation failed; previous binary retained.'
        }
        if ([IO.File]::Exists($dllPath)) {
            [IO.File]::Replace($stagedDll, $dllPath, [NullString]::Value)
        } else {
            [IO.File]::Move($stagedDll, $dllPath)
        }
        Write-Output "Built $dllPath"

        if ($env:APPDATA) {
            $rmUserDir = Join-Path $env:APPDATA 'Rainmeter'
            if (Test-Path -LiteralPath $rmUserDir -PathType Container) {
                $rmPluginsDir = Join-Path $rmUserDir 'Plugins'
                try {
                    [void][IO.Directory]::CreateDirectory($rmPluginsDir)
                    $rmDllPath = Join-Path $rmPluginsDir 'SlateHUD.dll'
                    Copy-Item -LiteralPath $dllPath -Destination $rmDllPath -Force -ErrorAction Stop
                    Write-Output "Synced $rmDllPath"
                } catch {
                    Write-Warning ("Could not overwrite locked Rainmeter plugin {0}: {1}" -f (Join-Path $rmPluginsDir 'SlateHUD.dll'), $_.Exception.Message)
                }
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $stagedDll -PathType Leaf) { Remove-Item -LiteralPath $stagedDll -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $buildTmp -PathType Container) { Remove-Item -LiteralPath $buildTmp -Recurse -Force -ErrorAction SilentlyContinue }
        Get-ChildItem -LiteralPath $pluginsDir -Filter 'SlateHUD.dll~RF*.TMP' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

if ($restart) { Start-Process -FilePath $helperPath -ArgumentList 'ensure' -WindowStyle Hidden }
