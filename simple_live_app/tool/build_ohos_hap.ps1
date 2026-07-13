param(
  [string]$FlutterRoot = "E:\slhm\work\flutter_ohos_commando_full",
  [string]$SdkRoot = "E:\slhm\work\harmonyos-cli-6.1.1.290\command-line-tools\sdk",
  [string]$JavaHome = "C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot",
  [string]$PubCache = "E:\slhm\work\pub-cache-ohos",
  [string]$SigningDir = "",
  [string]$KeystorePassword = $env:OHOS_KEYSTORE_PASSWORD,
  [string]$KeyPassword = $env:OHOS_KEY_PASSWORD
)

$ErrorActionPreference = "Stop"
$appRoot = Split-Path $PSScriptRoot -Parent
$cliRoot = Split-Path $SdkRoot -Parent
if ([string]::IsNullOrWhiteSpace($SigningDir)) {
  $SigningDir = Join-Path $appRoot "ohos\signing"
}
if ([string]::IsNullOrWhiteSpace($KeystorePassword) -or
    [string]::IsNullOrWhiteSpace($KeyPassword)) {
  throw "HarmonyOS signing passwords are required. Pass -KeystorePassword and -KeyPassword or set OHOS_KEYSTORE_PASSWORD and OHOS_KEY_PASSWORD."
}
$unsignedHap = Join-Path $appRoot "ohos\entry\build\default\outputs\default\entry-default-unsigned.hap"
$outputDir = Join-Path $appRoot "build\ohos\hap"
$signedHap = Join-Path $outputDir "simple_live_app-release-signed.hap"
$verifyDir = Join-Path $outputDir "verify"
$java = Join-Path $JavaHome "bin\java.exe"
$flutter = Join-Path $FlutterRoot "bin\flutter.bat"
$signTool = Join-Path $SdkRoot "default\openharmony\toolchains\lib\hap-sign-tool.jar"
$nativeRoot = Join-Path $SdkRoot "default\openharmony\native"
$cmake = Join-Path $nativeRoot "build-tools\cmake\bin\cmake.exe"
$quickJsSource = Join-Path $appRoot "third_party\quickjs_c_bridge\ohos"
$quickJsBuild = Join-Path $appRoot "build\ohos\quickjs"
$quickJsLibrary = Join-Path $appRoot "ohos\entry\libs\arm64-v8a\libfastdev_quickjs_runtime.so"
$launcherIconSource = Join-Path $appRoot "ios\Runner\Assets.xcassets\AppIcon.appiconset\icon-1024.png"
$launcherIconTarget = Join-Path $appRoot "ohos\entry\src\main\resources\base\media\icon.png"

$env:HOS_SDK_HOME = $SdkRoot
$env:JAVA_HOME = $JavaHome
$env:PUB_CACHE = $PubCache
$env:PATH = "$cliRoot\bin;$cliRoot\tool\node;$JavaHome\bin;$FlutterRoot\bin;$env:PATH"

Push-Location $appRoot
try {
  # Flutter's generated OHOS project contains a blue grid placeholder icon.
  # Keep the HarmonyOS media resource synchronized with Simple Live's real
  # high-resolution launcher artwork before every build.
  if (-not (Test-Path $launcherIconSource)) {
    throw "Simple Live launcher icon is missing: $launcherIconSource"
  }
  Copy-Item -LiteralPath $launcherIconSource -Destination $launcherIconTarget -Force

  & $cmake -S $quickJsSource -B $quickJsBuild -G Ninja `
    "-DCMAKE_MAKE_PROGRAM=$(Join-Path $nativeRoot 'build-tools\cmake\bin\ninja.exe')" `
    "-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $nativeRoot 'build\cmake\ohos.toolchain.cmake')" `
    "-DOHOS_ARCH=arm64-v8a" `
    "-DOHOS_STL=c++_static" `
    "-DCMAKE_BUILD_TYPE=Release"
  if ($LASTEXITCODE -ne 0) { throw "QuickJS OHOS configure failed." }
  & $cmake --build $quickJsBuild --config Release
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $quickJsLibrary)) {
    throw "QuickJS OHOS library build failed."
  }

  $profileArgs = @(
    "sign-profile", "-mode", "localSign",
    "-keyAlias", "openharmony application profile release",
    "-keyPwd", $KeyPassword,
    "-profileCertFile", (Join-Path $SigningDir "OpenHarmonyProfileRelease.pem"),
    "-inFile", (Join-Path $SigningDir "profile-release.json"),
    "-signAlg", "SHA256withECDSA",
    "-keystoreFile", (Join-Path $SigningDir "OpenHarmony.p12"),
    "-keystorePwd", $KeystorePassword,
    "-outFile", (Join-Path $SigningDir "profile-release.p7b")
  )
  & $java -jar $signTool $profileArgs
  if ($LASTEXITCODE -ne 0) { throw "Provision profile signing failed." }

  & $flutter build hap --release --target-platform ohos-arm64
  if ($LASTEXITCODE -ne 0) { throw "Flutter HAP build failed." }
  if (-not (Test-Path $unsignedHap)) { throw "Unsigned HAP was not produced: $unsignedHap" }

  New-Item -ItemType Directory -Force $outputDir | Out-Null
  $signArgs = @(
    "sign-app", "-mode", "localSign",
    "-keyAlias", "openharmony application release",
    "-keyPwd", $KeyPassword,
    "-appCertFile", (Join-Path $SigningDir "app-release-chain.pem"),
    "-profileFile", (Join-Path $SigningDir "profile-release.p7b"),
    "-profileSigned", "1",
    "-inFile", $unsignedHap,
    "-signAlg", "SHA256withECDSA",
    "-keystoreFile", (Join-Path $SigningDir "OpenHarmony.p12"),
    "-keystorePwd", $KeystorePassword,
    "-outFile", $signedHap,
    "-compatibleVersion", "12",
    "-signCode", "1"
  )
  & $java -jar $signTool $signArgs
  if ($LASTEXITCODE -ne 0) { throw "HAP signing failed." }

  New-Item -ItemType Directory -Force $verifyDir | Out-Null
  $verifyArgs = @(
    "verify-app",
    "-inFile", $signedHap,
    "-outCertChain", (Join-Path $verifyDir "cert-chain.cer"),
    "-outProfile", (Join-Path $verifyDir "profile.p7b")
  )
  & $java -jar $signTool $verifyArgs
  if ($LASTEXITCODE -ne 0) { throw "HAP signature verification failed." }

  $file = Get-Item $signedHap
  $hash = Get-FileHash -Algorithm SHA256 $signedHap
  Write-Host "HAP=$signedHap"
  Write-Host "SIZE=$($file.Length)"
  Write-Host "SHA256=$($hash.Hash)"
}
finally {
  Pop-Location
}
