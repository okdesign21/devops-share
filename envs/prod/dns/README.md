# Production DNS Stack - TODO
# This will be populated when ready for prod deployment  
# Copy from ../dev/dns/ and adjust for production requirements

# Key differences for prod:
# - Uses existing Route53 zone (data source, not resource)
# - Production app certificate
# - No CICD DNS records (GitLab/Jenkins only in dev)
# - Production ExternalDNS IRSA role