param([string]$Php = 'C:\xampp\php\php.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    # All database tests use dedicated regression schemas on localhost:33307.
    # rental_reputation includes the rental_integration fixtures and assertions.
    $suites = @('rental_reputation', 'api_entry', 'runtime', 'rental_subscription',
        'rental_upload', 'purchase_verification', 'oauth_verification',
        'auth_route_rules', 'server_configuration', 'app_updates', 'service_matching', 'notification_delivery')
    New-Item -ItemType Directory -Force -Path 'build/release-audit' | Out-Null
    foreach ($suite in $suites) {
        $logPath = "build/release-audit/backend-$suite.log"
        & $Php "test/backend/${suite}_test.php" *> $logPath
        if ($LASTEXITCODE -ne 0) {
            Get-Content $logPath -Tail 25
            throw "Backend test failed: $suite"
        }
        Get-Content $logPath -Tail 2
    }
    Get-ChildItem lib -Filter '*.php' | ForEach-Object {
        & $Php -l $_.FullName
        if ($LASTEXITCODE -ne 0) { throw "PHP syntax failed: $($_.Name)" }
    }
} finally { Pop-Location }
