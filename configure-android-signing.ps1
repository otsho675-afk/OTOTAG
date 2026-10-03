param([string]$KeystorePath = '')

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) {
    $studioKeytool = Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin\keytool.exe'
    if (Test-Path -LiteralPath $studioKeytool -PathType Leaf) { $keytool = $studioKeytool }
}
if (-not $keytool) { throw 'keytool bulunamadi. JDK veya Android Studio JBR bin klasorunu PATH listesine ekleyin.' }

if (-not $KeystorePath) { $KeystorePath = Read-Host 'Google Play icin mevcut keystore dosyanizin tam yolu' }
$KeystorePath = $KeystorePath.Trim().Trim('"')
$resolvedKeystore = (Resolve-Path -LiteralPath $KeystorePath).ProviderPath
if (-not (Test-Path -LiteralPath $resolvedKeystore -PathType Leaf)) { throw 'Keystore bir dosya olmali.' }

function Read-SigningSecret([string]$Prompt) {
    $secureValue = Read-Host $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secureValue.Dispose() }
}
function Escape-Property([string]$Value) {
    $builder = [Text.StringBuilder]::new()
    foreach ($character in $Value.ToCharArray()) {
        switch ($character) {
            "`r" { [void]$builder.Append('\r'); continue }
            "`n" { [void]$builder.Append('\n'); continue }
            "`t" { [void]$builder.Append('\t'); continue }
        }
        if ('\:=#! '.Contains([string]$character)) { [void]$builder.Append('\') }
        [void]$builder.Append($character)
    }
    return $builder.ToString()
}

$oldStoreEnvironment = $env:OTOTAG_SIGNING_SETUP_STORE_PASS
$oldKeyEnvironment = $env:OTOTAG_SIGNING_SETUP_KEY_PASS
$temporaryCsr = $null
try {
    $storePassword = Read-SigningSecret 'Keystore sifresi (ekranda gorunmez)'
    if (-not $storePassword) { throw 'Keystore sifresi bos olamaz.' }
    $env:OTOTAG_SIGNING_SETUP_STORE_PASS = $storePassword
    $ErrorActionPreference = 'Continue'
    $keyInfo = & $keytool '-J-Duser.language=en' '-J-Duser.country=US' -list -v -keystore $resolvedKeystore -storepass:env OTOTAG_SIGNING_SETUP_STORE_PASS 2>&1
    $listExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($listExit -ne 0) { throw 'Keystore acilamadi. Dosyayi ve keystore sifresini kontrol edin; mevcut ayarlar degistirilmedi.' }

    $aliases = @()
    $currentAlias = $null
    foreach ($line in $keyInfo) {
        $text = [string]$line
        if ($text -match '^Alias name:\s*(.+)$') { $currentAlias = $Matches[1].Trim() }
        if ($text -match '^Entry type:\s*PrivateKeyEntry' -and $currentAlias) { $aliases += $currentAlias }
    }
    if ($aliases.Count -eq 0) { throw 'Bu dosyada imzalama icin PrivateKeyEntry bulunamadi.' }
    if ($aliases.Count -eq 1) { $keyAlias = $aliases[0] }
    else {
        Write-Host ('Imzalama alias listesi: ' + ($aliases -join ', '))
        $keyAlias = Read-Host 'Google Play yukleme anahtarinin alias degeri'
        if ($keyAlias -notin $aliases) { throw 'Secilen alias keystore icinde yok.' }
    }

    $keyPassword = Read-SigningSecret 'Anahtar sifresi (keystore sifresiyle ayniysa Enter)'
    if (-not $keyPassword) { $keyPassword = $storePassword }
    $env:OTOTAG_SIGNING_SETUP_KEY_PASS = $keyPassword
    $temporaryCsr = [IO.Path]::GetTempFileName()
    $ErrorActionPreference = 'Continue'
    $verificationOutput = & $keytool '-J-Duser.language=en' -certreq -keystore $resolvedKeystore -alias $keyAlias -storepass:env OTOTAG_SIGNING_SETUP_STORE_PASS -keypass:env OTOTAG_SIGNING_SETUP_KEY_PASS -file $temporaryCsr 2>&1
    $verificationExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($verificationExit -ne 0) { throw 'Ozel anahtar acilamadi. Anahtar sifresini kontrol edin; mevcut ayarlar degistirilmedi.' }

    $properties = [ordered]@{
        storeFile = $resolvedKeystore.Replace('\','/')
        storePassword = $storePassword
        keyAlias = $keyAlias
        keyPassword = $keyPassword
    }
    $propertyLines = foreach ($entry in $properties.GetEnumerator()) { $entry.Key + '=' + (Escape-Property $entry.Value) }
    $destination = Join-Path $projectRoot 'android\key.properties'
    [IO.File]::WriteAllText($destination, ($propertyLines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host ('Mevcut anahtar dogrulandi. Alias: ' + $keyAlias)
    Write-Host 'android/key.properties kaydedildi; bu dosya Git tarafindan dislanir.'
    Write-Host 'Yeni keystore olusturulmadi. Simdi: flutter build appbundle --release'
} finally {
    $env:OTOTAG_SIGNING_SETUP_STORE_PASS = $oldStoreEnvironment
    $env:OTOTAG_SIGNING_SETUP_KEY_PASS = $oldKeyEnvironment
    if ($temporaryCsr -and (Test-Path -LiteralPath $temporaryCsr -PathType Leaf)) { Remove-Item -LiteralPath $temporaryCsr }
    $storePassword = $null
    $keyPassword = $null
    $properties = $null
}
