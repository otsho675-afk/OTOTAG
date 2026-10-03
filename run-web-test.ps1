# Google Console Web OAuth JavaScript origins: http://localhost and http://localhost:60369
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    flutter run -d chrome --web-hostname localhost --web-port 60369
} finally { Pop-Location }
