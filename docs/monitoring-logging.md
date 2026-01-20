# Monitoring, Logging, and Observability

## Overview

This document outlines the comprehensive monitoring, logging, and observability strategy for the Payment Form infrastructure.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Metrics & Events                        │
├─────────────────────────────────────────────────────────────┤
│ EC2 instances │ RDS Database │ S3 Buckets │ Lambda Functions │
└────────────────────────────────────────────────────────────┬┘
                                                                 │
                         ┌──────────────┬──────────────┬────────┴────┐
                         ▼              ▼              ▼             ▼
                   CloudWatch    X-Ray Traces   EventBridge    CloudTrail
                         │              │              │             │
                         └──────────────┴──────────────┴────────┬────┘
                                                                 │
                         ┌──────────────┬──────────────┬────────┴────┐
                         ▼              ▼              ▼             ▼
                   Dashboards      Alerts       Log Groups    Audit Logs
```

## CloudWatch Monitoring

### Metrics Collection

#### Application Metrics

```yaml
# ECS Task Metrics
- CPUUtilization
- MemoryUtilization
- Network In/Out
- TaskCount

# Custom Application Metrics
- Request Latency (p50, p95, p99)
- Request Count (by endpoint)
- Error Rate
- Payment Processing Time
```

#### Infrastructure Metrics

```yaml
# Database
- DatabaseConnections
- QueryTime
- ReplicationLag
- StorageUsed

# Network
- ALB TargetResponseTime
- TargetConnectionCount
- RequestCount
- HTTPCode responses

# Storage
- S3 ObjectCount
- S3 StorageSize
- Replication Status
```

### Creating Custom Metrics

```bash
# Push custom metric
aws cloudwatch put-metric-data \
  --namespace "PaymentForm/Backend" \
  --metric-name "PaymentProcessingTime" \
  --value 1250 \
  --unit Milliseconds \
  --dimensions Environment=prod,Service=backend

# Aggregate metrics
aws cloudwatch get-metric-statistics \
  --namespace "PaymentForm/Backend" \
  --metric-name "PaymentProcessingTime" \
  --start-time 2026-01-20T00:00:00Z \
  --end-time 2026-01-20T23:59:59Z \
  --period 3600 \
  --statistics Average,Maximum,Minimum
```

## Logging Strategy

### Log Groups Structure

```
/aws/paymentform/
├── /backend/
│   ├── /api/
│   ├── /workers/
│   └── /database/
├── /client/
│   ├── /nextjs/
│   └── /errors/
├── /renderer/
│   ├── /render-jobs/
│   └── /errors/
└── /infrastructure/
    ├── /terraform/
    ├── /ansible/
    └── /security/
```

### CloudWatch Logs Insights Queries

```sql
-- API Error Rate (Last 1 hour)
fields @timestamp, @message, status_code
| filter status_code >= 400
| stats count() as error_count by status_code
| sort error_count desc

-- Slow Queries (> 1000ms)
fields @timestamp, query_time, query
| filter query_time > 1000
| stats count() as slow_queries, avg(query_time) as avg_time
| sort slow_queries desc

-- Payment Processing Failures
fields @timestamp, payment_id, error_message
| filter event_type = "payment_failed"
| stats count() as failures by error_message

-- Authentication Failures
fields @timestamp, user_id, failure_reason
| filter event = "auth_failed"
| stats count() as failed_attempts by user_id
| filter failed_attempts > 5
```

### Log Retention

```bash
# Set log retention to 30 days
aws logs put-retention-policy \
  --log-group-name /aws/paymentform/backend \
  --retention-in-days 30

# Archive old logs to S3
aws logs create-export-task \
  --log-group-name /aws/paymentform/backend \
  --from 1704067200000 \
  --to 1706745600000 \
  --destination paymentform-log-archive \
  --destination-prefix "logs/backend/"
```

## Distributed Tracing (X-Ray)

### Enabling X-Ray

```bash
# Grant X-Ray write access
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
```

### Tracing Configuration in Application

```php
// Laravel: config/xray.php
return [
    'enabled' => env('XRAY_ENABLED', true),
    'daemon_address' => env('XRAY_DAEMON_ADDRESS', '127.0.0.1:2000'),
    'log_level' => env('XRAY_LOG_LEVEL', 'info'),
];
```

### Analyzing Traces

```bash
# Get trace summary
aws xray get-trace-summaries \
  --start-time 2026-01-20T00:00:00Z \
  --end-time 2026-01-20T23:59:59Z \
  --filter-expression 'http.status >= 400'

# Get detailed trace
aws xray get-trace-graph \
  --trace-ids "1-5e123456-78901234567890abcd"
```

## Alerting

### Alert Policy

| Severity | Response Time | Escalation |
|----------|---------------|-----------|
| CRITICAL | 5 minutes | Page on-call engineer |
| HIGH | 15 minutes | Page team lead |
| MEDIUM | 1 hour | Create ticket |
| LOW | Next business day | Create ticket |

### SNS Topics and Subscriptions

```bash
# Create SNS topics
aws sns create-topic --name paymentform-alerts-critical
aws sns create-topic --name paymentform-alerts-high
aws sns create-topic --name paymentform-alerts-medium

# Subscribe to alerts
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:paymentform-alerts-critical \
  --protocol sms \
  --notification-endpoint +1234567890

# Send test alert
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:paymentform-alerts-critical \
  --message "Test alert"
```

### CloudWatch Alarms

```bash
# High CPU usage
aws cloudwatch put-metric-alarm \
  --alarm-name backend-high-cpu \
  --alarm-description "Backend CPU > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:paymentform-alerts-high

# High database latency
aws cloudwatch put-metric-alarm \
  --alarm-name db-high-latency \
  --alarm-description "Database query latency > 500ms" \
  --metric-name AverageCpuUtilization \
  --namespace AWS/RDS \
  --statistic Average \
  --period 60 \
  --threshold 500 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:paymentform-alerts-critical

# Application error rate
aws cloudwatch put-metric-alarm \
  --alarm-name app-high-error-rate \
  --alarm-description "Error rate > 5%" \
  --metric-name ErrorRate \
  --namespace PaymentForm/Backend \
  --statistic Average \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:paymentform-alerts-high
```

## Dashboards

### CloudWatch Dashboard

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ECS", "CPUUtilization", {"stat": "Average"}],
          [".", "MemoryUtilization", {"stat": "Average"}],
          ["PaymentForm/Backend", "RequestLatency", {"stat": "p99"}],
          [".", "ErrorRate"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Backend Service Health"
      }
    }
  ]
}
```

## Security Monitoring

### CloudTrail Configuration

```bash
# Enable CloudTrail logging
aws cloudtrail create-trail \
  --name paymentform-trail \
  --s3-bucket-name paymentform-cloudtrail-logs \
  --is-multi-region-trail

# Start logging
aws cloudtrail start-logging --trail-name paymentform-trail

# Query suspicious activity
aws cloudtrail lookup-events \
  --max-results 50 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteDBCluster
```

### Security Metrics

- Failed login attempts (> 5 in 5 min)
- Unauthorized API calls
- IAM policy changes
- Security group modifications
- KMS key usage anomalies

## Performance Monitoring

### Key Performance Indicators (KPIs)

```sql
-- API Response Time (p95)
fields @timestamp, response_time
| stats pct(@response_time, 95) as p95_response_time by service

-- Payment Success Rate
fields payment_id, status
| stats count() as total_payments, count(if(status="success",1)) as successful_payments
| fields successful_payments * 100.0 / total_payments as success_rate

-- Database Connection Pool Utilization
fields @timestamp, active_connections, max_connections
| stats avg(active_connections/max_connections)*100 as pool_utilization
```

## Health Checks

### Application Health Endpoints

```bash
# Backend health check
curl -X GET https://api.paymentform.io/health
# Expected: { "status": "healthy", "version": "1.0.0" }

# Check database connection
curl -X GET https://api.paymentform.io/health/db
# Expected: { "db": "connected", "latency_ms": 5 }

# Check external services
curl -X GET https://api.paymentform.io/health/external
# Expected: { "razorpay": "connected", "aws": "connected" }
```

### Automated Health Checks

```bash
#!/bin/bash
# scripts/health-check.sh

SERVICES=("api.paymentform.io" "client.paymentform.io" "renderer.paymentform.io")

for service in "${SERVICES[@]}"; do
  response=$(curl -s -w "%{http_code}" https://$service/health)
  http_code="${response: -3}"
  
  if [ "$http_code" != "200" ]; then
    aws cloudwatch put-metric-data \
      --namespace PaymentForm/Health \
      --metric-name ServiceDown \
      --value 1 \
      --dimensions Service=$service
  fi
done
```

## Regular Reviews

### Daily

- [ ] Error logs from previous 24 hours
- [ ] Critical alerts
- [ ] Performance anomalies

### Weekly

- [ ] Trend analysis
- [ ] Capacity planning
- [ ] Cost analysis

### Monthly

- [ ] SLA review
- [ ] Alert threshold adjustment
- [ ] Dashboard updates

---

**Last Updated**: 2026-01-20
**Next Review**: 2026-04-20
