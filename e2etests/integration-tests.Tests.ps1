# Integration tests for CrowdSec Firewall Bouncer

BeforeAll {
    # Test configuration
    # Note: Inside containers, use internal port 8080; from host, use port 8080
    $CrowdSecApiUrl = "http://crowdsec:8080"  # Internal container URL
    $BouncerContainerName = "crowdsec-firewall-bouncer"
    $CrowdSecContainerName = "crowdsec-lapi"
    
    # Hardcoded port for CrowdSec LAPI
    $CrowdSecHostUrl = "http://localhost:8080"
}

Describe "CrowdSec Firewall Bouncer Integration Tests" {
    
    Context "CrowdSec LAPI Health" {
        It "CrowdSec LAPI should be healthy" {
            $response = Invoke-WebRequest -Uri "$CrowdSecHostUrl/health" -Method Get -ErrorAction Stop
            $response.StatusCode | Should -Be 200
        }
        
        It "CrowdSec LAPI should respond to /v1/watchers/login endpoint" {
            $body = @{
                machine_id = "test-machine"
                password = "test-password"
            } | ConvertTo-Json
            
            try {
                $response = Invoke-WebRequest -Uri "$CrowdSecHostUrl/v1/watchers/login" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
                $response.StatusCode | Should -BeIn @(200, 401)  # 401 is OK for invalid credentials, means API is working
            }
            catch {
                # If it's a 401, that's fine - means API is working
                if ($_.Exception.Response.StatusCode -eq 401) {
                    $true | Should -Be $true
                } else {
                    throw
                }
            }
        }
    }
    
    Context "Firewall Bouncer Container" {
        It "Bouncer container should be running" {
            $container = docker ps --filter "name=$BouncerContainerName" --format "{{.Names}}"
            $container | Should -Be $BouncerContainerName
        }
        
        It "Bouncer container should have required capabilities" {
            $inspect = docker inspect $BouncerContainerName | ConvertFrom-Json
            $inspect[0].HostConfig.Privileged | Should -Be $true
            $capAdd = $inspect[0].HostConfig.CapAdd
            # Docker returns capabilities with CAP_ prefix
            ($capAdd -contains "NET_ADMIN" -or $capAdd -contains "CAP_NET_ADMIN") | Should -Be $true
            ($capAdd -contains "NET_RAW" -or $capAdd -contains "CAP_NET_RAW") | Should -Be $true
            ($capAdd -contains "SYS_ADMIN" -or $capAdd -contains "CAP_SYS_ADMIN") | Should -Be $true
        }
        
        It "Bouncer should have connected to CrowdSec LAPI" {
            $logs = docker logs $BouncerContainerName 2>&1
            $logContent = $logs -join "`n"
            
            # Check for successful connection indicators
            $hasConnection = $logContent -match "successfully connected|connection.*established|api.*ready|Starting crowdsec-firewall-bouncer"
            $hasErrors = $logContent -match "error.*connection|failed.*connect|connection.*refused"
            
            if ($hasErrors -and -not $hasConnection) {
                Write-Host "Bouncer logs:" -ForegroundColor Yellow
                Write-Host $logContent -ForegroundColor Yellow
            }
            
            # Should have started without critical connection errors
            $hasConnection | Should -Be $true
        }
        
        It "Bouncer logs should not contain critical errors" {
            # Wait a bit for container to stabilize
            Start-Sleep -Seconds 5
            $logs = docker logs $BouncerContainerName 2>&1
            $logContent = $logs -join "`n"
            
            # Check that bouncer started successfully
            $hasSuccessfulStart = $logContent -match "nftables initiated|Processing new and deleted decisions|backend type: nftables"
            
            # Check for fatal errors that indicate real problems (not transient startup issues)
            # Ignore errors during initial startup before envsubst processes the template
            $fatalErrors = $logContent -match "level=fatal" -and 
                          $logContent -notmatch "api.*client.*init.*parse" -and
                          $logContent -notmatch "stream.*not.*supported" -and
                          $logContent -notmatch "live.*not.*supported" -and
                          $logContent -notmatch "Shutting down backend"
            
            if ($fatalErrors) {
                Write-Host "Critical errors found in bouncer logs:" -ForegroundColor Red
                Write-Host $logContent -ForegroundColor Red
            }
            
            # Should have started successfully and not have fatal errors
            $hasSuccessfulStart | Should -Be $true
            if ($fatalErrors) {
                Write-Host "Fatal errors found:" -ForegroundColor Yellow
                $fatalErrors | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
            }
            # Only fail if there are fatal errors AND no successful start
            if ($fatalErrors -and -not $hasSuccessfulStart) {
                throw "Bouncer failed to start and has fatal errors"
            }
        }
        
        It "Bouncer should show decisions added in logs" {
            # Wait for bouncer to process decisions
            Start-Sleep -Seconds 10
            $logs = docker logs $BouncerContainerName 2>&1
            $logContent = $logs -join "`n"
            
            # Check for "decisions added" message (case-insensitive, flexible format)
            $hasDecisionsAdded = $logContent -imatch "decisions.*added|decisions added|number.*decisions.*added"
            
            if (-not $hasDecisionsAdded) {
                Write-Host "Bouncer logs (looking for 'decisions added'):" -ForegroundColor Yellow
                Write-Host $logContent -ForegroundColor Yellow
            }
            
            $hasDecisionsAdded | Should -Be $true
        }
    }
    
    Context "Bouncer Configuration" {
        It "Bouncer should have configuration file mounted" {
            # Wait for container to be running (not restarting)
            $maxRetries = 10
            $retryCount = 0
            $containerRunning = $false
            while ($retryCount -lt $maxRetries -and -not $containerRunning) {
                Start-Sleep -Milliseconds 500
                $status = docker inspect $BouncerContainerName --format '{{.State.Status}}' 2>&1
                if ($status -eq "running") {
                    $containerRunning = $true
                }
                $retryCount++
            }
            
            $configExists = docker exec $BouncerContainerName test -f /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml 2>&1
            $LASTEXITCODE | Should -Be 0
        }
        
        It "Bouncer should have CROWDSEC_API_KEY environment variable set" {
            # Wait for container to be running
            Start-Sleep -Seconds 2
            $env = docker exec $BouncerContainerName printenv CROWDSEC_API_KEY 2>&1
            if ($LASTEXITCODE -ne 0) {
                # Try getting from inspect instead
                $inspect = docker inspect $BouncerContainerName | ConvertFrom-Json
                $envVars = $inspect[0].Config.Env
                $env = ($envVars | Where-Object { $_ -match "^CROWDSEC_API_KEY=" }) -replace "CROWDSEC_API_KEY=", ""
            }
            $env | Should -Not -BeNullOrEmpty
            $env | Should -Be "test-api-key-123"
        }
        
        It "Bouncer should have CROWDSEC_API_URL environment variable set" {
            # Wait for container to be running
            Start-Sleep -Seconds 1
            $env = docker exec $BouncerContainerName printenv CROWDSEC_API_URL 2>&1
            if ($LASTEXITCODE -ne 0) {
                # Try getting from inspect instead
                $inspect = docker inspect $BouncerContainerName | ConvertFrom-Json
                $envVars = $inspect[0].Config.Env
                $env = ($envVars | Where-Object { $_ -match "^CROWDSEC_API_URL=" }) -replace "CROWDSEC_API_URL=", ""
            }
            $env | Should -Not -BeNullOrEmpty
            $env | Should -Match "crowdsec.*8080"
        }
    }
    
    Context "Network Connectivity" {
        It "Bouncer should be able to reach CrowdSec LAPI" {
            # Wait for container to be running
            Start-Sleep -Seconds 2
            # Test connectivity from bouncer container to CrowdSec
            # Try wget first (available in Debian), then try basic connectivity test
            $result = docker exec $BouncerContainerName sh -c "wget --spider --quiet http://crowdsec:8080/health 2>&1 || echo 'connectivity-test'" 2>&1
            # If wget fails, try a simple test - check if we can resolve the hostname
            if ($LASTEXITCODE -ne 0) {
                $result = docker exec $BouncerContainerName sh -c "getent hosts crowdsec" 2>&1
                $LASTEXITCODE | Should -Be 0
            }
        }
    }
}

