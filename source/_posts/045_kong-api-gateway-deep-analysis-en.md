---
title: Deep Dive into Kong API Gateway
date: 2024-05-28
tags: 网关
categories: 后端
lang: en
label: 045_kong-api-gateway-deep-analysis
---

## Background

If you work with microservices, you can't avoid an API gateway. Whether you use Spring Cloud Gateway, Envoy, or hand-roll something with Nginx, you need a unified entry point to route requests to backend services.

Kong is one of the most mature open-source solutions in this space — 40K+ stars on GitHub, backed by a commercial company, with a solid plugin ecosystem and wide adoption at scale. But many developers stop at "oh, it's just a gateway" without digging into its architecture, plugin system, or configuration model. This article does a systematic breakdown across architecture, plugins, configuration, load balancing, and more.

<!-- more -->

## What is Kong

Kong is an open-source API gateway built on Nginx + OpenResty (LuaJIT). Its core capabilities cover route forwarding, authentication, traffic control, and observability. The fundamental problem it solves: extracting cross-cutting concerns like auth, rate limiting, and logging from individual business services and consolidating them at the gateway layer, so business services can focus purely on business logic.

| Scenario | Without gateway | With Kong |
|----------|----------------|-----------|
| 10 microservices need auth | Each service implements it | Kong handles it uniformly, services focus on business |
| Rate limit an endpoint | Write rate limiting code in the service | Configure a Kong plugin |
| Log all requests | Add logging code to every service | Kong collects them uniformly, zero business impact |
| Canary release | Change code or Nginx config | Kong splits traffic by weight, config takes effect immediately |

The traditional approach means building the same thing in every service. Kong centralizes these shared capabilities at the gateway layer. The more services you have, the bigger the payoff.

## Architecture Breakdown

### Overall Architecture

Kong Gateway's architecture has four layers. The top layer is the Nginx reverse proxy, handling all inbound requests. The second layer is the OpenResty/LuaJIT runtime, providing the Lua execution environment. The third layer is Kong Core — the route matching engine and plugin system (auth, rate limiting, logging, transformation plugins all run here). Kong Core also exposes an Admin API for configuration management. The bottom layer is the data store, supporting PostgreSQL, Cassandra, or declarative config files. The data plane's job is to forward requests to the upstream services (User Service, Order Service, etc.).

### Why Nginx + OpenResty

Kong didn't go with Java or Go — it chose Lua, a relatively niche language. The reason: OpenResty. OpenResty is an enhanced Nginx that embeds LuaJIT into Nginx's request processing lifecycle, bringing three key capabilities:

1. Extremely high performance: Nginx is already known for high concurrency, and LuaJIT runs close to C speed
2. Non-blocking I/O: OpenResty wraps all network operations as non-blocking — a request waiting for a database response doesn't block other requests
3. Lifecycle hooks: Every Nginx processing phase (rewrite, access, content, log) can be extended with Lua

Kong is essentially an Nginx config generator plus a plugin execution engine, written in Lua and running on OpenResty.

### Core Abstraction Model

Kong's configuration revolves around five core concepts. A Service abstracts an upstream backend service, including URL, protocol, and timeout settings. A Route defines request matching rules — which requests get routed to which Service, based on path, Host, HTTP Method, etc. One Service can have multiple Routes. An Upstream is a collection of Targets (backend instance addresses) responsible for load balancing strategy and health checks. A Consumer represents an API caller identity, identified via API Key, JWT, etc. A Plugin abstracts cross-cutting logic and can be attached to a Service, Route, or Consumer.

A practical example:

```yaml
# Define a service
Service:
  name: user-service
  url: http://user-api.internal:8080

# Define routes for this service
Route:
  name: user-route
  paths: ["/api/v1/users"]
  methods: ["GET", "POST"]
  service: user-service

# Add auth plugin to the route
Plugin:
  name: key-auth
  route: user-route
```

The design logic is clean: Service abstracts the backend, Route abstracts matching rules, Plugin abstracts cross-cutting logic — decoupled, each doing its own job.

### Request Lifecycle

When a request arrives at Kong, it goes through these phases in order:

1. SSL/TLS handshake (certificate phase): mTLS plugin can execute here
2. URI rewrite (rewrite phase): URL rewrite plugins execute here
3. Route matching: Kong finds the matching Route based on Host/Path/Method
4. Auth (access phase): key-auth, jwt, oauth2 plugins execute
5. Rate limiting (access phase): rate-limiting, quota plugins execute
6. Request transformation (access phase): request-transformer plugin executes
7. Forward request to upstream service
8. Receive upstream response
9. Response header handling (header_filter phase): cors, response-transformer plugins execute
10. Response body handling (body_filter phase): can modify response content
11. Logging (log phase): tcp-log, http-log, file-log plugins execute
12. Return response to client

The access phase is where most of the action happens — most plugins execute here. Each plugin has a priority; higher priority plugins run first.

## Plugin System

The plugin system is Kong's biggest differentiator from other gateways. Understanding the plugin system is the key to truly understanding Kong.

### Plugin Scope

Kong supports layered plugin configuration at four levels, from broadest to narrowest. Global plugins apply to all requests. Service-level plugins apply to all requests for a specific Service. Route-level plugins apply to requests matching a specific Route. Consumer-level plugins apply to requests from a specific Consumer.

This layered design is extremely flexible in practice. Enable CORS globally, apply stricter rate limiting for the payment service, relax quota limits for VIP consumers — all through different plugin layer combinations.

### Plugin Execution Mechanism

Each plugin is essentially a Lua module implementing specific hook functions:

```lua
-- A minimal Kong plugin example
local MyPlugin = {
  PRIORITY = 1000,  -- Priority: higher runs first
  VERSION = "1.0.0",
}

-- Logic executed in the access phase
function MyPlugin:access(conf)
  -- Get a header from the request
  local request_id = kong.request.get_header("X-Request-ID")
  
  if not request_id then
    -- No request_id — return 400 immediately
    return kong.response.exit(400, {
      message = "Missing X-Request-ID header"
    })
  end
  
  -- Pass request_id to the upstream service
  kong.service.request.set_header("X-Request-ID", request_id)
end

return MyPlugin
```

Kong provides a PDK (Plugin Development Kit) that wraps all common operations:

| PDK Function | Purpose |
|-------------|---------|
| `kong.request.get_header()` | Get request header |
| `kong.request.get_body()` | Get request body |
| `kong.response.exit()` | Return response directly |
| `kong.service.request.set_header()` | Modify headers sent to upstream |
| `kong.client.get_consumer()` | Get current consumer info |
| `kong.ip.get_source()` | Get client's real IP |

### Built-in Plugin Categories

Kong's built-in plugins cover several major categories.

Authentication:

| Plugin | Description |
|--------|-------------|
| key-auth | API Key auth — simplest and most common |
| jwt | JWT Token authentication |
| oauth2 | Full OAuth 2.0 flow |
| basic-auth | HTTP Basic authentication |
| hmac-auth | HMAC signature authentication |
| ldap-auth | LDAP directory authentication |
| openid-connect | OIDC authentication (integrates with Okta, Auth0, etc.) |
| mtls-auth | Mutual TLS authentication |

Traffic control:

| Plugin | Description |
|--------|-------------|
| rate-limiting | Rate limiting by IP/Consumer/Service |
| request-size-limiting | Limit request body size |
| proxy-cache | Response caching |
| canary | Canary release — traffic splitting by weight |

Transformation:

| Plugin | Description |
|--------|-------------|
| request-transformer | Modify request headers, body, URL params |
| response-transformer | Modify response headers, body |
| request-validator | JSON Schema request validation |
| correlation-id | Generate unique request identifier |
| cors | CORS configuration |

Observability:

| Plugin | Description |
|--------|-------------|
| prometheus | Expose Prometheus metrics |
| datadog | Datadog APM integration |
| zipkin | Distributed tracing |
| tcp-log | Send logs via TCP |
| http-log | Send logs via HTTP |
| file-log | Write to local file |
| kafka-log | Send to Kafka |

### Building a Custom Plugin

The built-in plugins cover most scenarios, but sometimes you need your own. Say you want to add internal audit logging for all requests passing through the gateway — that requires a custom plugin.

Directory structure:

```
kong-plugin-audit-log/
├── kong/
│   └── plugins/
│       └── audit-log/
│           ├── handler.lua    # Plugin logic
│           └── schema.lua     # Config validation
└── kong-plugin-audit-log-0.1.0-1.rockspec
```

handler.lua contains the main logic, collecting request info in the log phase and sending it to the audit system:

```lua
local AuditLog = {
  PRIORITY = 10,
  VERSION = "1.0.0",
}

function AuditLog:log(conf)
  -- Collect request info
  local request = {
    method = kong.request.get_method(),
    path = kong.request.get_path(),
    query = kong.request.get_raw_query(),
    headers = kong.request.get_headers(),
    client_ip = kong.client.get_ip(),
    consumer = kong.client.get_consumer(),
    service = kong.router.get_service(),
    response_status = kong.response.get_status(),
    request_id = kong.request.get_header("X-Request-ID"),
  }
  
  -- Serialize and send to audit system
  local cjson = require("cjson")
  local log_data = cjson.encode(request)
  
  -- Send to Kafka or HTTP endpoint
  local http = require("resty.http")
  local httpc = http.new()
  httpc:request_uri(conf.audit_endpoint, {
    method = "POST",
    body = log_data,
    headers = {
      ["Content-Type"] = "application/json",
    },
  })
end

return AuditLog
```

schema.lua defines the plugin's configuration validation rules:

```lua
return {
  name = "audit-log",
  fields = {
    { consumer = typedefs.no_consumer },
    { config = {
        type = "record",
        fields = {
          { audit_endpoint = { type = "string", required = true } },
          { include_headers = { type = "boolean", default = true } },
        },
      },
    },
  },
}
```

Install and enable the plugin:

```bash
# Package
luarocks make

# Enable in kong.conf
plugins = bundled,audit-log

# Or via environment variable
KONG_PLUGINS=bundled,audit-log
```

### Multi-Language Plugin Support

Not everyone knows Lua, so Kong later added External Plugins support for other languages:

| Language | Method | Description |
|----------|--------|-------------|
| Go | Go PDK | Communicates with Kong via gRPC |
| Python | Python PDK | Also via gRPC |
| JavaScript | JS PDK | Also via gRPC |
| WebAssembly | WASM | Next-gen extension method |

The principle is the same: Kong calls the external plugin service via gRPC during plugin execution; the external service processes and returns the result. Performance is lower than native Lua plugins, but the development barrier is much lower — teams don't need to learn Lua to extend Kong.

## Configuration Management

Kong supports three configuration modes for different deployment scenarios.

#### Traditional Database Mode (DB Mode)

All configuration (Service, Route, Plugin, Consumer) is stored in PostgreSQL or Cassandra and managed via Admin API. Changes take effect immediately without a restart. Multiple Kong nodes share the same configuration. This suits dynamic environments where services frequently come and go. The trade-off is dependency on a database — if the database goes down, existing request forwarding continues (Kong has a local cache), but configuration changes become impossible.

#### DB-less Declarative Mode

All configuration lives in a YAML file, loaded at startup:

```yaml
# kong.yml
_format_version: "3.0"

services:
  - name: user-service
    url: http://user-api:8080
    routes:
      - name: user-route
        paths: ["/api/users"]
    plugins:
      - name: key-auth
      - name: rate-limiting
        config:
          minute: 100
          policy: local

  - name: order-service
    url: http://order-api:8080
    routes:
      - name: order-route
        paths: ["/api/orders"]
```

Start with the config file:

```bash
kong start -c kong.conf --declarative-config kong.yml
```

No database needed — simpler deployment, config-as-code manageable via Git, naturally suited for GitOps and CI/CD pipelines, and can be placed directly in a Kubernetes ConfigMap. The limitation is that config changes require a reload, and dynamic Consumer registration isn't supported.

#### Hybrid Mode

Kong separates the control plane from the data plane. The control plane manages configuration, connects to the database, and exposes the Admin API. The data plane only does proxy forwarding — no database, no Admin API. The control plane pushes config to data planes via mTLS; data planes cache config locally and continue processing requests even if the control plane is temporarily unavailable.

| Component | Responsibility | Characteristics |
|-----------|---------------|-----------------|
| Control plane | Config management, database connection | Exposes Admin API, centrally manages all config |
| Data plane | Proxy and forward requests | No database, no Admin API, caches config locally |

This mode is more secure (data plane doesn't expose management interfaces), lighter to deploy (no database needed), and supports cross-datacenter centralized management. The trade-off is increased architectural complexity and mTLS certificate management.

## Load Balancing and Service Discovery

Kong implements load balancing through Upstream objects, supporting multiple algorithms:

| Algorithm | Description | Use case |
|-----------|-------------|---------|
| round-robin | Round robin | General purpose, most common |
| consistent-hashing | Consistent hashing | Sessions need to stick |
| least-connections | Least connections | Backend instances have uneven performance |
| latency | Lowest latency | Latency-sensitive scenarios |

Consistent hashing deserves special mention — it can hash on different dimensions, giving you a lot of flexibility:

```bash
# Hash by Consumer — same consumer always hits the same backend
curl -X POST http://localhost:8001/upstreams/my-upstream \
  --data name=my-upstream \
  --data hash_on=consumer

# Hash by IP
curl -X POST http://localhost:8001/upstreams/my-upstream \
  --data name=my-upstream \
  --data hash_on=ip

# Hash by a specific header
curl -X POST http://localhost:8001/upstreams/my-upstream \
  --data name=my-upstream \
  --data hash_on=header \
  --data hash_on_header=X-User-ID
```

### Health Checks

Kong provides two health check mechanisms, typically used together. Active checks send probe requests to backend instances at regular intervals, judging health by HTTP status code. Passive checks are based on actual request failures — also called circuit breaking — marking an instance unhealthy when TCP failures, timeouts, or HTTP errors hit a threshold.

```bash
# Active check config
curl -X POST http://localhost:8001/upstreams/my-upstream/healthcheck \
  --data active.healthy.interval=5 \
  --data active.unhealthy.interval=2 \
  --data active.http_path=/health \
  --data active.http_statuses=200,302

# Passive check config (circuit breaking)
curl -X POST http://localhost:8001/upstreams/my-upstream/healthcheck \
  --data passive.healthy.successes=5 \
  --data passive.unhealthy.tcp_failures=3 \
  --data passive.unhealthy.timeouts=3 \
  --data passive.unhealthy.http_failures=5
```

### Service Discovery

Kong supports integration with service discovery systems:

| Method | Description |
|--------|-------------|
| DNS SRV | Discover services via DNS records |
| Consul | HashiCorp Consul integration |
| Kubernetes | Use K8s Service names directly |

Kubernetes integration is the most common. In a K8s environment, Kong uses Service names as upstreams and auto-resolves ClusterIPs — no manual backend instance list maintenance:

```yaml
services:
  - name: user-service
    url: http://user-service.default.svc.cluster.local:8080
```

## Quick Start

#### One-Command Docker Setup

The simplest approach is Docker Compose for a complete Kong environment:

```yaml
# docker-compose.yml
version: "3.8"

services:
  kong-database:
    image: postgres:15
    environment:
      POSTGRES_USER: kong
      POSTGRES_DB: kong
      POSTGRES_PASSWORD: kong
    volumes:
      - kong-db-data:/var/lib/postgresql/data

  kong-migrations:
    image: kong:3.6
    command: kong migrations bootstrap
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
    depends_on:
      - kong-database

  kong:
    image: kong:3.6
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
    ports:
      - "8000:8000"   # Proxy
      - "8443:8443"   # Proxy SSL
      - "8001:8001"   # Admin API
    depends_on:
      - kong-database
      - kong-migrations

volumes:
  kong-db-data:
```

Start:

```bash
docker-compose up -d
```

#### Configure Your First API

Use the Admin API to register a service and route, then verify forwarding works:

```bash
# 1. Create service
curl -X POST http://localhost:8001/services \
  --data "name=httpbin" \
  --data "url=https://httpbin.org"

# 2. Create route
curl -X POST http://localhost:8001/services/httpbin/routes \
  --data "name=httpbin-route" \
  --data "paths[]=/httpbin"

# 3. Test
curl http://localhost:8000/httpbin/get
```

#### Add Authentication and Rate Limiting

```bash
# 1. Enable key-auth plugin
curl -X POST http://localhost:8001/services/httpbin/plugins \
  --data "name=key-auth"

# 2. Create consumer
curl -X POST http://localhost:8001/consumers \
  --data "username=app-001"

# 3. Assign API Key to consumer
curl -X POST http://localhost:8001/consumers/app-001/key-auth \
  --data "key=my-secret-api-key"

# 4. Test (without key)
curl http://localhost:8000/httpbin/get
# Returns 401 Unauthorized

# 5. Test (with key)
curl http://localhost:8000/httpbin/get \
  -H "apikey: my-secret-api-key"
# Returns data normally

# 6. Enable rate limiting plugin
curl -X POST http://localhost:8001/services/httpbin/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=10" \
  --data "config.policy=local"
```

#### DB-less Mode

Skip the database entirely with a declarative config file:

```yaml
# kong.yml
_format_version: "3.0"

services:
  - name: httpbin
    url: https://httpbin.org
    routes:
      - name: httpbin-route
        paths: ["/httpbin"]
    plugins:
      - name: rate-limiting
        config:
          minute: 100
          policy: local

consumers:
  - username: app-001
    keyauth_credentials:
      - key: my-secret-api-key
```

```bash
# Start in DB-less mode
KONG_DATABASE=off kong start -c kong.conf --declarative-config kong.yml
```

## Enterprise Scenarios

#### Multi-Environment Management

Real projects typically have dev, staging, and production environments — separate Kong instances with different ports for isolation:

```bash
# Dev Kong
KONG_PROXY_LISTEN=0.0.0.0:8000
KONG_ADMIN_LISTEN=0.0.0.0:8001

# Production Kong
KONG_PROXY_LISTEN=0.0.0.0:9000
KONG_ADMIN_LISTEN=0.0.0.0:9001
```

#### Canary Releases

Kong's Canary plugin supports weighted traffic splitting:

```bash
# 90% traffic to v1, 10% to v2
curl -X POST http://localhost:8001/services/my-service/plugins \
  --data "name=canary" \
  --data "config.upstream_host=v2.internal" \
  --data "config.upstream_port=8080" \
  --data "config.percentage=10"
```

#### API Version Management

Use Route priority for API versioning — higher priority routes match first:

```bash
# v1 route (lower priority)
curl -X POST http://localhost:8001/services/user-v1/routes \
  --data "name=user-v1" \
  --data "paths[]=/api/v1/users" \
  --data "priority=1"

# v2 route (higher priority, overrides v1)
curl -X POST http://localhost:8001/services/user-v2/routes \
  --data "name=user-v2" \
  --data "paths[]=/api/v2/users" \
  --data "priority=10"
```

#### CORS Handling

CORS is common in microservice architectures — handle it uniformly at the gateway layer with the CORS plugin instead of configuring each backend service individually:

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  --data "name=cors" \
  --data "config.origins=https://app.example.com" \
  --data "config.methods=GET,POST,PUT,DELETE" \
  --data "config.headers=Content-Type,Authorization" \
  --data "config.max_age=3600"
```

## Kong vs Other Solutions

There are several API gateway options. Here's how the major ones compare:

| Dimension | Kong | Spring Cloud Gateway | Envoy | APISIX |
|-----------|------|---------------------|-------|--------|
| Language | Lua | Java | C++ | Lua |
| Performance | Very high | Medium | Very high | Very high |
| Plugin ecosystem | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| Dynamic config | ✅ | ✅ | ✅ | ✅ |
| Management UI | Enterprise edition | Build your own | None | Yes |
| Learning curve | Medium | Low (Java ecosystem) | High | Medium |
| K8s integration | Ingress Controller | Weak | Native support | Ingress Controller |
| Best for | General purpose | Spring Cloud stack | Service Mesh | General purpose |

Selection guidance: Java-heavy tech stack → Spring Cloud Gateway. Service Mesh architecture → Envoy. General purpose with strong plugin ecosystem needs → Kong or APISIX. For mid-to-large microservice architectures, Kong is a mature, reliable choice — once service count scales up, the benefits of a unified gateway far outweigh operational costs. Small teams or simple setups might be fine hand-rolling Nginx configs.

## Caveats and Limitations

### Performance Considerations

Kong's own latency overhead is typically 1-5ms (excluding plugin processing), but latency climbs noticeably as plugin count increases. Real benchmark data shows: no plugins — ~1ms latency, 50K+ RPS throughput; 3 plugins — ~3ms latency, 30K+ RPS; 5+ plugins — 5-10ms latency, 20K+ RPS. Only enable the plugins you actually need.

### Admin API Security

The Admin API is Kong's management interface, listening on port 8001 by default with full control over configuration. In production, you must restrict access — either internal-only or with authentication:

```bash
# Internal access only
KONG_ADMIN_LISTEN=127.0.0.1:8001

# Or add authentication
KONG_ADMIN_GUI_AUTH=basic-auth
```

### Configuration Backup and Monitoring

In DB mode, back up PostgreSQL regularly. In DB-less mode, make sure kong.yml is version-controlled in Git — losing config is painful. Set up logging and monitoring in production early. The recommended stack: Prometheus plugin for metrics, Grafana for visualization, http-log or kafka-log for request log persistence.

## References

- [Kong Official Documentation](https://docs.konghq.com/)
- [Kong GitHub Repository](https://github.com/Kong/kong)
- [Kong Plugin Documentation](https://docs.konghq.com/hub/)
- [OpenResty Official Documentation](https://openresty.org/en/)
