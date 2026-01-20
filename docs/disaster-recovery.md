# Disaster Recovery & Business Continuity

## Overview

This document outlines the disaster recovery (DR) and business continuity procedures for the Payment Form infrastructure deployed across multiple AWS regions.

## RTO and RPO Targets

| Component | RTO | RPO | Strategy |
|-----------|-----|-----|----------|
| Backend | 1 hour | 5 minutes | Aurora with read replicas + cross-region backup |
| Client | 2 hours | 15 minutes | S3 + CloudFront replication |
| Renderer | 1.5 hours | 10 minutes | ECS service with auto-scaling |
| Databases | 30 minutes | 5 minutes | Aurora global database |

## Backup Strategy

### Database Backups

- **Primary (US East)**: Automated daily snapshots retained for 30 days
- **Replicas (EU West, AP Southeast)**: Read-only replicas in each region, promotes to standalone in 10-15 minutes
- **Turso**: Multi-region with automatic failover
- **Cross-Region Backup**: Nightly copy of snapshots to secondary regions

#### Backup Commands

```bash
# Create manual snapshot
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier paymentform-primary \
  --db-cluster-snapshot-identifier paymentform-backup-$(date +%Y%m%d-%H%M%S)

# List snapshots
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier paymentform-primary

# Test restore (to separate cluster)
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier paymentform-restore-test \
  --snapshot-identifier paymentform-backup-YYYYMMDD-HHMMSS
```

### Storage Backups (S3)

- **Versioning**: Enabled on all S3 buckets
- **Lifecycle Policy**: Move old versions to Glacier after 90 days
- **Cross-Region Replication**: Real-time replication to backup regions
- **Point-in-Time Recovery**: Available for last 30 days

#### Verify Replication

```bash
# Check replication status
aws s3api get-bucket-replication \
  --bucket paymentform-prod-storage

# List replicated objects in backup bucket
aws s3 ls s3://paymentform-prod-storage-backup/ \
  --recursive --summarize
```

### Application Backups

- **Docker Images**: Tagged by version, stored in ECR
- **Configuration**: Version controlled in Git with secrets in Secrets Manager
- **Database Dumps**: Weekly exports to S3

#### Create Application Backup

```bash
# Export database
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier paymentform-primary \
  --db-cluster-snapshot-identifier weekly-backup-$(date +%Y%m%d)

# Export database to S3 (parquet format)
aws rds start-export-task \
  --export-task-identifier weekly-export-$(date +%Y%m%d) \
  --source-arn arn:aws:rds:us-east-1:ACCOUNT:cluster:paymentform-primary \
  --s3-bucket-name paymentform-backup-exports \
  --s3-prefix exports/
```

## Failure Scenarios and Recovery

### Scenario 1: Single Region Failure (US East)

**Impact**: Backend service unavailable

**Recovery Steps**:
1. Verify replica health in EU West (5 mins)
2. Promote EU West replica to standalone cluster (10 mins)
3. Update Route53 weighted routing to EU West (1 min)
4. Deploy backend services to new cluster (5 mins)
5. Monitor traffic migration (ongoing)

```bash
# Promote read replica to standalone
aws rds promote-read-replica \
  --db-instance-identifier paymentform-eu-replica

# Update Route53
aws route53 change-resource-record-sets \
  --hosted-zone-id ZONE_ID \
  --change-batch file://failover-route53.json

# Deploy to new cluster
ansible-playbook -i inventory/production playbooks/deploy-backend.yml \
  -e "db_host=paymentform-eu-replica.c9akciq32.eu-west-1.rds.amazonaws.com"
```

**Total Recovery Time**: ~25 minutes

### Scenario 2: Database Corruption

**Impact**: Data integrity issue

**Recovery Steps**:
1. Identify corruption point in transaction logs (5 mins)
2. Restore from backup snapshot to point-in-time (10 mins)
3. Validate data integrity (5 mins)
4. Switch application connections (2 mins)
5. Run consistency checks (10 mins)

```bash
# Restore to specific point in time
aws rds restore-db-cluster-to-point-in-time \
  --db-cluster-identifier paymentform-recovered \
  --source-db-cluster-identifier paymentform-primary \
  --restore-type "copy-on-write" \
  --restore-to-time "2026-01-20T10:30:00Z"

# Run validation queries
./scripts/validate-database-integrity.sh
```

**Total Recovery Time**: ~30 minutes

### Scenario 3: Data Loss Event

**Impact**: All data lost or deleted

**Recovery Steps**:
1. Identify backup point (2 mins)
2. Restore from automated backup (15 mins)
3. Verify backup integrity (5 mins)
4. Promote to production (2 mins)
5. Validate all services (10 mins)

```bash
# List available backups
aws rds describe-db-cluster-snapshots \
  --query 'DBClusterSnapshots[?DBClusterIdentifier==`paymentform-primary`]' \
  --output table

# Restore from backup
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier paymentform-production-restored \
  --snapshot-identifier paymentform-backup-YYYYMMDD-HHMMSS \
  --engine aurora-mysql

# Promote to primary
aws rds modify-db-cluster \
  --db-cluster-identifier paymentform-production-restored \
  --apply-immediately
```

**Total Recovery Time**: ~35 minutes

### Scenario 4: Malicious Activity / Ransomware

**Impact**: Critical - potential data encryption or deletion

**Immediate Actions**:
1. Isolate affected resources (disable auto-scaling, detach from load balancer)
2. Activate incident response playbook
3. Snapshot current state for forensics
4. Restore from last known good backup
5. Review CloudTrail logs

```bash
# Isolate affected services
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name backend-asg \
  --desired-capacity 0

# Take snapshots for forensics
aws ec2 create-snapshots \
  --instance-specifications 'InstanceId=i-xxxxx,ExcludeBootVolume=false' \
  --description "Forensics snapshot - potential security incident"

# Review suspicious activity
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteDBCluster \
  --max-results 50
```

**Total Recovery Time**: ~1 hour + investigation

## Testing and Validation

### Monthly Disaster Recovery Drill

```bash
# Run complete DR test
./scripts/disaster-recovery-test.sh --environment staging --scenario full-failover

# Expected output:
# ✓ Backup validation passed
# ✓ Replica promotion successful
# ✓ Route53 failover completed
# ✓ Service health checks passed
# ✓ Data consistency verified
```

### Quarterly Full Restore Test

- Restore from oldest available backup
- Verify all data accessibility
- Test application functionality
- Measure recovery time
- Document findings and improvements

## Monitoring and Alerting

### Key Metrics to Monitor

```bash
# Database replica lag
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraBinlogReplicaLag \
  --dimensions Name=DBClusterIdentifier,Value=paymentform-primary \
  --start-time 2026-01-20T00:00:00Z \
  --end-time 2026-01-20T23:59:59Z \
  --period 300 \
  --statistics Average,Maximum
```

### Alert Configuration

- Replication lag > 10 seconds: WARNING
- Snapshot backup failure: CRITICAL
- Automated backup not completed: WARNING
- Read replica unhealthy: CRITICAL
- Cross-region replication lag > 5 minutes: WARNING

## Runbooks

See `/docs/runbooks/` for detailed step-by-step procedures:
- [Database Failover](./runbooks/database-failover.md)
- [Application Recovery](./runbooks/application-recovery.md)
- [Data Restoration](./runbooks/data-restoration.md)
- [Incident Response](./runbooks/incident-response.md)

## Contact and Escalation

**On-Call Engineer**: Check PagerDuty rotation
**Backup Contact**: SRE Team Lead
**Critical Incident**: VP Engineering

## Recovery Validation Checklist

- [ ] All services responding to health checks
- [ ] Database replication lag < 5 seconds
- [ ] Application latency within normal range
- [ ] All scheduled jobs resuming
- [ ] Log aggregation working
- [ ] Monitoring and alerting active
- [ ] Customer communications sent

---

**Last Updated**: 2026-01-20
**Next Review**: 2026-04-20
