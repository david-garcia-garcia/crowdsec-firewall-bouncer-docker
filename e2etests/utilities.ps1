# Utility functions for integration tests

function Wait-For-LogMessage {
    param(
        [string]$ContainerName,
        [string]$Pattern,
        [int]$TimeoutSeconds = 30,
        [int]$CheckIntervalSeconds = 2
    )
    
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $logContent = Get-ContainerLogs -ContainerName $ContainerName
        
        if ($logContent -imatch $Pattern) {
            return $true
        }
        
        Start-Sleep -Seconds $CheckIntervalSeconds
        $elapsed += $CheckIntervalSeconds
    }
    
    return $false
}

function Get-ContainerLogs {
    param(
        [string]$ContainerName
    )
    
    $logs = docker logs $ContainerName 2>&1
    return $logs -join "`n"
}

function Get-ContainerInspect {
    param(
        [string]$ContainerName
    )
    
    return docker inspect $ContainerName | ConvertFrom-Json
}

function Get-ContainerEnvironmentVariable {
    param(
        [string]$ContainerName,
        [string]$VariableName
    )
    
    # Try getting from printenv first
    $env = docker exec $ContainerName printenv $VariableName 2>&1
    if ($LASTEXITCODE -eq 0) {
        return $env
    }
    
    # Fallback to inspect
    $inspect = Get-ContainerInspect -ContainerName $ContainerName
    $envVars = $inspect[0].Config.Env
    $env = ($envVars | Where-Object { $_ -match "^${VariableName}=" }) -replace "${VariableName}=", ""
    return $env
}

function Wait-For-ContainerRunning {
    param(
        [string]$ContainerName,
        [int]$MaxRetries = 10,
        [int]$RetryIntervalMs = 500
    )
    
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        $status = docker inspect $ContainerName --format '{{.State.Status}}' 2>&1
        if ($status -eq "running") {
            return $true
        }
        Start-Sleep -Milliseconds $RetryIntervalMs
        $retryCount++
    }
    
    return $false
}

function Test-ContainerConnectivity {
    param(
        [string]$ContainerName,
        [string]$Url
    )
    
    # Try wget first (available in Debian)
    docker exec $ContainerName sh -c "wget --spider --quiet $Url 2>&1 || echo 'connectivity-test'" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return $true
    }
    
    # Fallback to hostname resolution test
    $hostname = ([System.Uri]$Url).Host
    docker exec $ContainerName sh -c "getent hosts $hostname" 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

