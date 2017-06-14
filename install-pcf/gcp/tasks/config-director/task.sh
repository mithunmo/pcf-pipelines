#!/bin/bash

set -eu

iaas_configuration=$(cat <<-EOF
  echo '{}' |
  jq \
    --arg $gcp_project "$GCP_PROJECT_ID" \
    --arg $default_deployment_tag "$GCP_RESOURCE_PREFIX" \
    --arg $auth_json "$GCP_SERVICE_ACCOUNT_KEY" \
    '. +
    {
      "project": $gcp_project,
      "default_deployment_tag": $default_deployment_tag,
      "auth_json": $auth_json
    }
    '
EOF
)

availability_zones="${GCP_ZONE_1},${GCP_ZONE_2},${GCP_ZONE_3}"

az_configuration=$(
  echo '{}' |
  jq \
    --arg availability_zones "$availability_zones" \
    '. +
    {
      "availability_zones": ($availability_zones | split(",") | map({name: .}))
    }'
EOF
)

network_configuration=$(
  echo '{}' |
  jq \
    --argjson icmp_checks_enabled false \
    --arg infra_network_name "infrastructure" \
    --arg infra_vcenter_network "${GCP_RESOURCE_PREFIX}-virt-net/${GCP_RESOURCE_PREFIX}-subnet-infrastructure-${GCP_REGION}/${GCP_REGION}" \
    --arg infra_network_cidr "192.168.101.0/26" \
    --arg infra_reserved_ip_ranges "192.168.101.1-192.168.101.9" \
    --arg infra_dns "192.168.101.1,8.8.8.8" \
    --arg infra_gateway "192.168.101.1" \
    --arg infra_availability_zones "$availability_zones" \
    --arg deployment_network_name "ert" \
    --arg deployment_vcenter_network "${GCP_RESOURCE_PREFIX}-virt-net/${GCP_RESOURCE_PREFIX}-subnet-ert-${GCP_REGION}/${GCP_REGION}" \
    --arg deployment_network_cidr "192.168.16.0/22" \
    --arg deployment_reserved_ip_ranges "192.168.16.1-192.168.16.9" \
    --arg deployment_dns "192.168.16.1,8.8.8.8" \
    --arg deployment_gateway "192.168.16.1" \
    --arg deployment_availability_zones "$availability_zones" \
    --argjson services_network_is_service_network true \
    --arg services_network_name "services-1" \
    --arg services_vcenter_network "${GCP_RESOURCE_PREFIX}-virt-net/${GCP_RESOURCE_PREFIX}-subnet-services-1-${GCP_REGION}/${GCP_REGION}" \
    --arg services_network_cidr "192.168.20.0/22" \
    --arg services_reserved_ip_ranges "192.168.20.1-192.168.20.9" \
    --arg services_dns "192.168.20.1,8.8.8.8" \
    --arg services_gateway "192.168.20.1" \
    --arg services_availability_zones "$availability_zones" \
    '. +
    {
      "icmp_checks_enabled": $icmp_checks_enabled,
      "networks": [
        {
          "name": $infra_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $infra_vcenter_network,
              "cidr": $infra_network_cidr,
              "reserved_ip_ranges": $infra_reserved_ip_ranges,
              "dns": $infra_dns,
              "gateway": $infra_gateway,
              "availability_zones": ($infra_availability_zones | split(","))
            }
          ]
        },
        {
          "name": $deployment_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $deployment_vcenter_network,
              "cidr": $deployment_network_cidr,
              "reserved_ip_ranges": $deployment_reserved_ip_ranges,
              "dns": $deployment_dns,
              "gateway": $deployment_gateway,
              "availability_zones": ($deployment_availability_zones | split(","))
            }
          ]
        },
        {
          "name": $services_network_name,
          "service_network": $services_network_is_service_network,
          "subnets": [
            {
              "iaas_identifier": $services_vcenter_network,
              "cidr": $services_network_cidr,
              "reserved_ip_ranges": $services_reserved_ip_ranges,
              "dns": $services_dns,
              "gateway": $services_gateway,
              "availability_zones": ($services_availability_zones | split(","))
            }
          ]
        },
        {
          "name": $dynamic_services_network_name,
          "service_network": true,
          "subnets": [
            {
              "iaas_identifier": $dynamic_services_vcenter_network,
              "cidr": $dynamic_services_network_cidr,
              "reserved_ip_ranges": $dynamic_services_reserved_ip_ranges,
              "dns": $dynamic_services_dns,
              "gateway": $dynamic_services_gateway,
              "availability_zones": ($dynamic_services_availability_zones | split(","))
            }
          ]
        }
      ]
    }'
)

director_config=$(cat <<-EOF
{
  "ntp_servers_string": "0.pool.ntp.org",
  "resurrector_enabled": "1",
  "retry_bosh_deploys": "1",
  "database_type": "internal",
  "blobstore_type": "local",
}
EOF
)

security_configuration=$(
  echo '{}' |
  jq \
    --arg trusted_certificates "" \
    '. +
    {
      "trusted_certificates": $trusted_certificates,
      "vm_password_type": "generate"
    }'
)

network_assignment=$(
echo '{}' |
jq \
  --arg availability_zones "$availability_zones" \
  --arg network "infrastructure" \
  '. +
  {
    "singleton_availability_zone": ($availability_zones | split(",") | .[0]),
    "network": $network
  }'
)

echo "Configuring IaaS and Director..."
om-linux \
  --target https://$OPS_MGR_HOST \
  --skip-ssl-validation \
  --username $OPS_MGR_USR \
  --password $OPS_MGR_PWD \
  configure-bosh \
  --iaas-configuration "$iaas_configuration" \
  --director-configuration "$director_config" \
  --az-configuration "$az_configuration" \
  --networks-configuration "$network_configuration" \
  --network-assignment "$network_assignment" \
  --security-configuration "$security_configuration"
