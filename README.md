# CrowdSec Firewall Bouncer Docker Image

Docker image for CrowdSec Firewall Bouncer with nftables support, optimized for Kubernetes deployments.

## Features

- Pre-installed CrowdSec firewall bouncer with nftables support
- Template-based configuration using `envsubst`
- Kubernetes-ready sidecar container
- Minimal Debian-based image

## Usage

### Creating a Bouncer Key

Before deploying the bouncer, you need to create an API key in CrowdSec. There are two methods:

#### Method 1: Using cscli (Recommended for manual setup)

```bash
# Connect to your CrowdSec container or server
cscli bouncers add firewall-bouncer --key <your-api-key>
```

Or let CrowdSec generate a key:

```bash
cscli bouncers add firewall-bouncer
# Output will show the generated API key
```

#### Method 2: Using Environment Variable (Recommended for automated deployments)

Set an environment variable on the CrowdSec container/service:

```yaml
# Docker Compose example
services:
  crowdsec:
    environment:
      - BOUNCER_KEY_FIREWALL_BOUNCER=your-api-key-here
```

```yaml
# Kubernetes example
env:
- name: BOUNCER_KEY_FIREWALL_BOUNCER
  value: "your-api-key-here"
```

The format is `BOUNCER_KEY_<NAME>` where `<NAME>` is your bouncer identifier. CrowdSec will automatically create the bouncer with this key on startup.

### Kubernetes Sidecar

Add the CrowdSec Firewall Bouncer as a sidecar container:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: crowdsec-bouncer-config
data:
  crowdsec-firewall-bouncer.yaml.template: |
    api_url: ${CROWDSEC_API_URL}
    api_key: ${CROWDSEC_API_KEY}
    mode: nftables
    update_frequency: 10s
    daemonize: false
    log_level: info
    log_media: stdout
    log_dir: /var/log
    pid_dir: /var/run
    nftables:
      enabled: true
      ipv4_table: crowdsec
      ipv6_table: crowdsec6
      ipv4_chain: crowdsec-chain
      ipv6_chain: crowdsec-chain
---
apiVersion: v1
kind: Secret
metadata:
  name: crowdsec-api-key
type: Opaque
stringData:
  api_key: "your-api-key-here"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: your-app:v1.0.0
      
      # CrowdSec Firewall Bouncer sidecar
      - name: crowdsec-firewall-bouncer
        image: YOUR_USERNAME/crowdsec-firewall-bouncer:v1.0.0-debian-12-bouncer-0.0.34
        security_context:
          privileged: true
          allow_privilege_escalation: true
          capabilities:
            add: ["NET_ADMIN", "NET_RAW", "SYS_ADMIN"]
        env:
        - name: CROWDSEC_API_URL
          value: "http://crowdsec-service:8080"
        - name: CROWDSEC_API_KEY
          valueFrom:
            secretKeyRef:
              name: crowdsec-api-key
              key: api_key
        volumeMounts:
        - name: crowdsec-bouncer-config
          mountPath: /tmp/crowdsec-config-source
        - name: crowdsec-bouncer-var-log
          mountPath: /var/log
        - name: crowdsec-bouncer-var-run
          mountPath: /var/run
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
      volumes:
      - name: crowdsec-bouncer-config
        configMap:
          name: crowdsec-bouncer-config
      - name: crowdsec-bouncer-var-log
        emptyDir: {}
      - name: crowdsec-bouncer-var-run
        emptyDir: {}
```

### Terraform Example

```hcl
dynamic "container" {
  for_each = var.crowdsec_firewall_bouncer_enabled && var.crowdsec_api_key != null && var.crowdsec_api_key != "" ? [1] : []
  
  content {
    name  = "crowdsec-firewall-bouncer"
    image = var.crowdsec_firewall_bouncer_image

    command = ["/bin/bash"]
    args    = ["/entrypoint.sh"]

    security_context {
      privileged                = true
      allow_privilege_escalation = true
      capabilities {
        add = ["NET_ADMIN", "NET_RAW", "SYS_ADMIN"]
      }
    }

    env {
      name  = "CROWDSEC_API_URL"
      value = var.crowdsec_api_url
    }

    env {
      name = "CROWDSEC_API_KEY"
      value_from {
        secret_key_ref {
          name = kubernetes_secret.crowdsec_api_key[0].metadata[0].name
          key  = "api_key"
        }
      }
    }

    volume_mount {
      name       = "crowdsec-bouncer-config"
      mount_path = "/tmp/crowdsec-config-source"
    }

    volume_mount {
      name       = "crowdsec-bouncer-var-log"
      mount_path = "/var/log"
    }

    volume_mount {
      name       = "crowdsec-bouncer-var-run"
      mount_path = "/var/run"
    }

    resources {
      requests = {
        cpu    = "50m"
        memory = "64Mi"
      }
      limits = {
        cpu    = "200m"
        memory = "256Mi"
      }
    }
  }
}
```

## Configuration

The bouncer uses a configuration template processed with `envsubst` at runtime.

### Configuration Paths

- **Template**: `/tmp/crowdsec-config-source/crowdsec-firewall-bouncer.yaml.template`
- **Output**: `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml`

### Environment Variables

All environment variables starting with `CROWDSEC_` are automatically substituted:

- `CROWDSEC_API_URL`: CrowdSec API URL (default: `http://127.0.0.1:8080`)
- `CROWDSEC_API_KEY`: API key (required)

### Template Syntax

```yaml
api_url: ${CROWDSEC_API_URL}
api_key: ${CROWDSEC_API_KEY}
```

## Local Testing

```bash
# Build and start services
docker compose up -d

# Run integration tests
./Test-Integration.ps1

# Clean up
docker compose down -v
```

## Building

Versions are managed in `.env`:

```bash
DEBIAN_VERSION=12
CROWDSEC_BOUNCER_VERSION=0.0.34
```

Build:

```bash
docker compose build
```

## Requirements

- Kubernetes cluster with privileged container support
- CrowdSec API instance
- Network access between bouncer and API

## References

- [CrowdSec Documentation](https://docs.crowdsec.net/)
- [CrowdSec Firewall Bouncer](https://docs.crowdsec.net/docs/bouncers/firewall-bouncer/)
