# Integration Tests

This directory contains integration tests for the CrowdSec Firewall Bouncer Docker image.

## Test Structure

- `integration-tests.Tests.ps1` - Main Pester test suite

## Running Tests

Run tests using the test runner script from the repository root:

```powershell
./Test-Integration.ps1
```

## Test Coverage

The integration tests verify:

1. **CrowdSec LAPI Health** - Verifies the CrowdSec API is running and responding
2. **Firewall Bouncer Container** - Checks container status, capabilities, and logs
3. **Bouncer Configuration** - Validates configuration file and environment variables
4. **Network Connectivity** - Ensures bouncer can communicate with CrowdSec LAPI

## Prerequisites

- Docker and Docker Compose
  - **Windows users**: The test script will automatically switch Docker Desktop to Linux containers if needed
- PowerShell 7+
- Pester 5.5.0+ (installed automatically if missing)

## Debugging

To keep services running after tests for debugging:

```powershell
./Test-Integration.ps1 -SkipDockerCleanup
```

Then manually inspect containers:

```powershell
# View bouncer logs
docker logs crowdsec-firewall-bouncer

# View CrowdSec logs
docker logs crowdsec-lapi

# Execute commands in bouncer container
docker exec -it crowdsec-firewall-bouncer sh

# Check network connectivity
docker exec crowdsec-firewall-bouncer curl http://crowdsec:8080/health
```

