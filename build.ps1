# ZMK local build script for catbox0624 (nice_nano_v2)
# Requires: Docker Desktop

param(
    [switch]$Clean,       # Force full rebuild
    [switch]$Update,      # Force west update
    [switch]$Init,        # Force west init (first time or west.yml changed)
    [switch]$NoCache      # Don't use docker cache when building image (N/A here)
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

$IMAGE = "zmkfirmware/zmk-build-arm:stable"
$BOARD = "nice_nano_v2"
$SHIELD = "catbox0624"
$SNIPPET = "studio-rpc-usb-uart"
$CMAKE_ARGS = "-DCONFIG_ZMK_STUDIO=y"
$ARTIFACT_NAME = "catbox0624"
$BUILD_DIR = "build/$ARTIFACT_NAME"

$WEST_YML = "$ProjectRoot/config/west.yml"
$HASH_FILE = "$ProjectRoot/.west-modules-hash"

# -------------------------------------------------------------------
function Invoke-Docker {
    param([string]$Cmd)
    Write-Host "[docker] $Cmd" -ForegroundColor Cyan
    docker run --rm -v "${ProjectRoot}:/workspace" -w /workspace $IMAGE bash -c $Cmd
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed" }
}

# -------------------------------------------------------------------
Write-Host "=== ZMK Build: $SHIELD ($BOARD) ===" -ForegroundColor Green

# Pull latest image
Write-Host "Pulling docker image..." -ForegroundColor Yellow
docker pull $IMAGE

# Determine if west init is needed
$needInit = $false
$needUpdate = $false

if ($Init) {
    $needInit = $true
    $needUpdate = $true
}
elseif (-not (Test-Path "$ProjectRoot/.west")) {
    Write-Host "No .west directory found, will run west init." -ForegroundColor Yellow
    $needInit = $true
    $needUpdate = $true
}

# Determine if west update is needed
if ($Update) {
    $needUpdate = $true
}
elseif (-not $needInit) {
    $currentHash = (Get-FileHash $WEST_YML -Algorithm MD5).Hash
    $savedHash = ""
    if (Test-Path $HASH_FILE) {
        $savedHash = Get-Content $HASH_FILE
    }
    if ($currentHash -ne $savedHash) {
        Write-Host "west.yml changed, will run west update." -ForegroundColor Yellow
        $needUpdate = $true
    }
}

# West init
if ($needInit) {
    Write-Host "Running west init..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "$ProjectRoot/.west" -ErrorAction SilentlyContinue
    Invoke-Docker -Cmd "west init -l /workspace/config"
}

# West update
if ($needUpdate) {
    Write-Host "Running west update (this may take a while on first run)..." -ForegroundColor Yellow
    Invoke-Docker -Cmd "west update --narrow -o=--depth=1"
    # Save hash after successful update
    (Get-FileHash $WEST_YML -Algorithm MD5).Hash | Set-Content $HASH_FILE
}

# Always do zephyr-export (fast)
Write-Host "Running west zephyr-export..." -ForegroundColor Yellow
Invoke-Docker -Cmd "west zephyr-export"

# Clean build if requested
if ($Clean) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "$ProjectRoot/$BUILD_DIR" -ErrorAction SilentlyContinue
}

# Build
$shieldArg = if ($SHIELD) { "-DSHIELD=$SHIELD" } else { "" }
$snippetArg = if ($SNIPPET) { "-S $SNIPPET" } else { "" }
$cmakeArgs = if ($CMAKE_ARGS) { $CMAKE_ARGS } else { "" }

Write-Host "Building..." -ForegroundColor Yellow
docker run --rm -v "${ProjectRoot}:/workspace" -w /workspace $IMAGE bash -c @"
west build -s zmk/app -b $BOARD -d /workspace/$BUILD_DIR $shieldArg $snippetArg $cmakeArgs -DZMK_EXTRA_MODULES=/workspace/zephyr
"@
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

# Copy output
$srcUf2 = "$ProjectRoot/$BUILD_DIR/zephyr/zmk.uf2"
$destUf2 = "$ProjectRoot/$ARTIFACT_NAME.uf2"

if (Test-Path $srcUf2) {
    Copy-Item $srcUf2 $destUf2 -Force
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  BUILD SUCCESS!" -ForegroundColor Green
    Write-Host "  Output: $destUf2" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "BUILD FAILED: No .uf2 file found at $srcUf2" -ForegroundColor Red
    Write-Host "Check the build output above for errors." -ForegroundColor Red
    exit 1
}
