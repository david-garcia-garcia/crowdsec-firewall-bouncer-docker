#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Runs integration tests for the CrowdSec Firewall Bouncer Docker Container
#>

[CmdletBinding()]
param(
    [switch]$SkipDockerCleanup,
    [switch]$SkipWait
)

$ErrorActionPreference = "Stop"

function Write-Step { param([string]$Message) Write-Host "🔄 $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }

Write-Host ""
Write-Host "🚀 CrowdSec Firewall Bouncer Integration Test Runner" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# Check Pester
Write-Step "Checking Pester availability..."
try {
    Import-Module Pester -Force -ErrorAction Stop
    Write-Success "Pester is available"
} catch {
    Write-Error "Pester module not found. Install with: Install-Module -Name Pester -Force -Scope CurrentUser"
    exit 1
}

# Check Docker Compose
Write-Step "Checking Docker Compose availability..."
$null = docker compose version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Compose is not available"
    exit 1
}
Write-Success "Docker Compose is available"

# Check Docker container mode (Windows)
Write-Step "Checking Docker configuration..."
$dockerInfo = docker info 2>&1 | Out-String
if ($dockerInfo -match "OSType.*windows") {
    Write-Step "Switching to Linux containers..."
    $dockerDesktopPath = "C:\Program Files\Docker\Docker\DockerCli.exe"
    if (Test-Path $dockerDesktopPath) {
        & $dockerDesktopPath -SwitchLinuxEngine
        Start-Sleep -Seconds 10
        $dockerInfo = docker info 2>&1 | Out-String
        if ($dockerInfo -match "OSType.*windows") {
            Write-Error "Failed to switch to Linux containers. Please switch manually."
            exit 1
        }
    } else {
        Write-Error "Docker Desktop CLI not found. Please switch to Linux containers manually."
        exit 1
    }
}
Write-Success "Docker is configured for Linux containers"

# Build Docker images
Write-Step "Building Docker images..."
docker compose build
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build Docker images"
    exit 1
}
Write-Success "Docker images built successfully"

# Start Docker services
Write-Step "Starting Docker Compose services..."
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to start Docker services"
    exit 1
}
Write-Success "Docker services started successfully"

# Wait for services
if (-not $SkipWait) {
    Write-Step "Waiting for CrowdSec LAPI to be ready..."
    $elapsed = 0
    do {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -Method Get -TimeoutSec 2 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Success "CrowdSec LAPI is ready!"
                break
            }
        } catch {
            Start-Sleep -Seconds 2
            $elapsed += 2
            if ($elapsed -ge 60) {
                Write-Error "CrowdSec LAPI failed to start"
                docker compose logs crowdsec
                exit 1
            }
        }
    } while ($true)
    
    Write-Step "Waiting for firewall bouncer to connect..."
    Start-Sleep -Seconds 10
    Write-Success "Services are ready!"
}

# Run Pester tests
Write-Step "Running Pester integration tests..."
Write-Host ""

$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = "./e2etests"
$pesterConfig.Output.Verbosity = 'Detailed'
$pesterConfig.Run.Exit = $false
$pesterConfig.Run.PassThru = $true

$result = Invoke-Pester -Configuration $pesterConfig

Write-Host ""
if ($result -and $result.FailedCount -eq 0) {
    Write-Success "All integration tests passed! 🎉"
    $exitCode = 0
} else {
    Write-Error "$($result.FailedCount) test(s) failed out of $($result.TotalCount) total tests"
    $exitCode = 1
}

# Cleanup
if (-not $SkipDockerCleanup) {
    Write-Step "Cleaning up Docker services..."
    docker compose down -v 2>$null
    Write-Success "Docker services stopped and cleaned up"
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
if ($exitCode -eq 0) {
    Write-Host "🏁 Integration tests completed successfully!" -ForegroundColor Green
} else {
    Write-Host "🏁 Integration tests completed with failures!" -ForegroundColor Red
}
Write-Host ""

exit $exitCode
