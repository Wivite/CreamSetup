function FindSteamID {
    param (
        [string]$GamePath
    )
    
    try {
        $SteamRoot = (Split-Path (Split-Path $GamePath))
    } catch {
        return "0"
    }

    $Value = Get-ChildItem -Path $SteamRoot -Recurse -Filter "*.acf" | ForEach-Object {
        if ((Get-Content $_) -like "*installdir*`"$(Split-Path $GamePath -Leaf)`"*") {
            return $_ -replace ".*_" -replace ".acf"
        }
    }

    if ($null -ne $Value) {
        return $Value
    } else {
        return "0"
    }
}

$CreamIniPath = Join-Path $PSScriptRoot "cream_api.ini"
$CreamDllPath = Join-Path $PSScriptRoot "steam_api.dll"
$Cream64DllPath = Join-Path $PSScriptRoot "steam_api64.dll"

$MissingFile = ""
if ((@($CreamIniPath, $CreamDllPath, $Cream64DllPath) | Where-Object { 
    if ((Test-Path $_) -eq $false) {
        Set-Variable MissingFile $_
        return $true
    } else {
        return $false
    }
}).Count -ne 0) {
    Write-Error "Missing `"$(Split-Path $MissingFile -Leaf)`" in $($PSScriptRoot)"
    return
}

$InstallPath = Read-Host "Game installation path"
$GameIdStr = FindSteamID $InstallPath

if ($GameIdStr -eq "0") {
    Write-Host "No game id found for $($InstallPath) enter it manually"
    $GameIdStr = Read-Host "Game Id"
}

try {
    [System.Convert]::ToUInt64($GameIdStr) | Out-Null
}
catch {
    Write-Error "`"$($GameIdStr)`" is not a valid ID."
    return
}

if ((Test-Path $InstallPath) -eq $false) {
    Write-Error "Path `"$($InstallPath)`" does not exist."
    return
}

$Index = -1
$SteamDlls = (Get-ChildItem -Path $InstallPath -Recurse -Include "steam_api*.dll" -Exclude "*_o.dll")
if ($SteamDlls.GetType() -ne [System.IO.FileInfo]) {
    $i = 0
    $SteamDlls | ForEach-Object {
        Write-Host "$($i+1). $($_)"
        $i += 1
    }
    try {
        $Index = [UInt64](Read-Host "SteamAPI to replace")
    } catch {
        Write-Error $_.Exception.Message
        return
    }

    if ($Index -gt $SteamDlls.Length || $Index -lt 1) {
        Write-Error "$($Index) is not in range (1-$($SteamDlls.Length))"
        return
    }

    $SteamDll = $SteamDlls[$Index-1]
} else {
    $SteamDll = $SteamDlls
}

if ($null -eq $SteamDll) {
    Write-Error "Somehow got oob of SteamAPI array ?"
    return
}

if ((Test-Path (Join-Path $SteamDll.Directory.ToString() "cream_api.ini")) -eq $true) {
    Write-Error "CreamAPI already installed in `"$($SteamDll.Directory)`""
    return
}

$CreamPath = $SteamDll.Directory
Copy-Item $CreamIniPath -Destination $CreamPath

if ($SteamDll -like "*steam_api64.dll") {
    Rename-Item (Join-Path $CreamPath "steam_api64.dll") "steam_api64_o.dll"
    Copy-Item $Cream64DllPath -Destination $CreamPath
} else {
    Rename-Item (Join-Path $CreamPath "steam_api.dll") "steam_api_o.dll"
    Copy-Item $CreamDllPath -Destination $CreamPath
}

try {
    $response = Invoke-WebRequest -Uri "https://store.steampowered.com/api/appdetails?appids=$($GameIdStr)"
    $StatusCode = $response.StatusCode
}
catch {
    $StatusCode = $_.Exception.Response.StatusCode.value__
    Write-Error "Failed to get App details for $($GameIdStr) with code: $($StatusCode)"
    return
}

$AppData = $response.Content | ConvertFrom-Json
$Dlcs = $AppData.$GameIdStr.data.dlc
Write-Host "Found $($Dlcs.Length) Dlc(s) for `"$($AppData.$GameIdStr.data.name)`""

$GameIniPath = Join-Path $CreamPath "cream_api.ini"
(Get-Content -Path $GameIniPath) -replace "appid = 0", "appid = $($GameIdStr)" `
    | Set-Content -Path $GameIniPath

$Added = 0
$Dlcs | ForEach-Object {
    try {
        $DlcResponse = Invoke-WebRequest -Uri "https://store.steampowered.com/api/appdetails?appids=$($_)"
        $StatusCode = $DlcResponse.StatusCode
    } catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        Write-Error "Failed to get App details for dlc $($_) with code: $($StatusCode)"
        return
    }
    $DlcData = $DlcResponse.Content | ConvertFrom-Json
    Add-Content $GameIniPath "$($_) = $($DlcData.$_.data.name)"
    Write-Host "Added: $($DlcData.$_.data.name)"
    $Added += 1
}

Write-Host "Added $($Added) Dlc(s)"
