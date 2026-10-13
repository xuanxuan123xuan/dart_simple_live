$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$videoOutput = Join-Path $repoRoot 'third_party\media_kit_video\android\src\main\java\com\alexmercerind\media_kit_video\VideoOutput.java'
$textureUpdateCallback = Join-Path $repoRoot 'third_party\media_kit_video\android\src\main\java\com\alexmercerind\media_kit_video\TextureUpdateCallback.java'
$testSourceRoot = Join-Path $PSScriptRoot 'src'
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$buildRoot = Join-Path $tempRoot ('dart-simple-live-native-surface-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $buildRoot | Out-Null
try {
    $javaSources = @($videoOutput, $textureUpdateCallback) + @(
        Get-ChildItem -LiteralPath $testSourceRoot -Recurse -Filter '*.java' |
            ForEach-Object { $_.FullName }
    )

    & javac --release 17 -d $buildRoot $javaSources
    if ($LASTEXITCODE -ne 0) {
        throw "javac failed with exit code $LASTEXITCODE"
    }

    & java -cp $buildRoot com.alexmercerind.media_kit_video.VideoOutputBehaviorTest
    if ($LASTEXITCODE -ne 0) {
        throw "Java behavior test failed with exit code $LASTEXITCODE"
    }
} finally {
    $resolvedBuildRoot = [System.IO.Path]::GetFullPath($buildRoot)
    $tempChildPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedBuildRoot.StartsWith($tempChildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete build path outside the temp directory: $resolvedBuildRoot"
    }
    Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
}
