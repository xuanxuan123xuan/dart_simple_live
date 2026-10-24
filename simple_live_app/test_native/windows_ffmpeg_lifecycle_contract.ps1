$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginPath = Join-Path $repoRoot 'third_party/ffmpeg_kit_flutter_new/windows/ffmpeg_kit_flutter_plugin.cpp'
$headerPath = Join-Path $repoRoot 'third_party/ffmpeg_kit_flutter_new/windows/ffmpeg_kit_flutter_plugin.h'
$cmakePath = Join-Path $repoRoot 'third_party/ffmpeg_kit_flutter_new/windows/CMakeLists.txt'
$cApiPath = Join-Path $repoRoot 'third_party/ffmpeg_kit_flutter_new/windows/ffmpeg_kit_flutter_plugin_c_api.cpp'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'

$source = Get-Content -LiteralPath $pluginPath -Raw
$header = Get-Content -LiteralPath $headerPath -Raw
$cmake = Get-Content -LiteralPath $cmakePath -Raw
$cApi = Get-Content -LiteralPath $cApiPath -Raw
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw

function Assert-Contains([string] $text, [string] $pattern, [string] $message) {
    if ($text -notmatch $pattern) {
        throw $message
    }
}

function Assert-NotContains([string] $text, [string] $pattern, [string] $message) {
    if ($text -match $pattern) {
        throw $message
    }
}

Assert-Contains $pubspec 'ffmpeg_kit_flutter_new:\s*\r?\n\s+path:\s+third_party/ffmpeg_kit_flutter_new' `
    'The app must resolve FFmpegKit from the repository-local fork.'
Assert-Contains $source 'GET_MODULE_HANDLE_EX_FLAG_PIN' `
    'libffmpegkit must be pinned until process termination.'
Assert-Contains $source 'if\s*\(lib_\s*&&\s*lib_pinned_for_process_\)\s*\{\s*FreeLibrary\(lib_\)' `
    'Only the successfully process-pinned library may release its LoadLibrary reference.'
Assert-NotContains $source 'g_plugin_instance' `
    'Native callbacks must not retain a raw plugin pointer.'
Assert-NotContains $source 'std::thread\s*\(\s*\[this\b' `
    'Detached native workers must not capture the plugin object.'
Assert-Contains $source 'state->EnqueueEvent\(' `
    'Native callbacks must dispatch through shared state.'
Assert-Contains $source 'if\s*\(!attached_\)' `
    'Shared state must reject callback and task delivery after detaching.'
Assert-Contains $header 'std::shared_ptr<PluginAsyncState> async_state_' `
    'The plugin must own a shared async callback/task state.'
Assert-Contains $cmake 'extern\s+"C"\s*\{' `
    'The generated Windows public header must declare the C ABI wrapper.'
Assert-Contains $cmake 'FFmpegKitFlutterPluginRegisterWithRegistrar\s*\(\s*FlutterDesktopPluginRegistrarRef\s+registrar\s*\);' `
    'The generated Windows public header must declare the plugin registration function.'
Assert-Contains $cApi '#include\s+"include/ffmpeg_kit_flutter_new/f_fmpeg_kit_flutter_plugin\.h"' `
    'The Windows C API implementation must include the generated public header.'
Assert-Contains $cmake 'file\(WRITE\s+"\$\{PUBLIC_HEADER_DIR\}/f_fmpeg_kit_flutter_plugin\.h"' `
    'The generated Windows public header path must match the implementation include.'

$destructorStart = $source.IndexOf('FFmpegKitFlutterPlugin::~FFmpegKitFlutterPlugin()')
if ($destructorStart -lt 0) {
    throw 'Could not find the Windows plugin destructor.'
}
$destroyWindow = $source.IndexOf('DestroyWindow(msg_hwnd_)', $destructorStart)
$detachState = $source.IndexOf('async_state_->Detach()', $destructorStart)
if ($detachState -lt 0 -or $destroyWindow -lt 0 -or $detachState -gt $destroyWindow) {
    throw 'The shared state must detach before its message window is destroyed.'
}

Write-Output 'Windows FFmpegKit lifecycle contract passed.'
