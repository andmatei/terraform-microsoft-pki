# Create a new directory
New-Item -Path "C:\HSM" -ItemType Directory -Force

# Change to the new directory
Set-Location -Path "C:\HSM"

# Get cluster CSR
# aws cloudhsmv2 describe-clusters --filters clusterIds="${cluster_id}" --output text --query "Clusters[].Certificates.ClusterCsr" | Out-File -FilePath ".\clusterCSR.csr" -Encoding utf8
$cluster = Get-HSM2Cluster -Filter @{clusterIds = "${cluster_id}"}
$csr = $cluster.Certificates.ClusterCsr
$csr | Out-File -FilePath ".\clusterCSR.csr" -Encoding utf8

# Create private key
openssl genrsa  -out customerCA.key 2048

# Create self-signed certificate
openssl req -new -x509 -days 3652 -key customerCA.key -out customerCA.crt

# Sign the cluster CSR
openssl x509 -req -days 3652 -in clusterCSR.csr -CA customerCA.crt -CAkey customerCA.key  -CAcreateserial -out customerHsmCertificate.crt

# # Initialize cluster
# aws cloudhsmv2 initialize-cluster --cluster-id "${cluster_id}" --signed-cert .\customerHsmCertificate.crt --trust-anchor .\customerCA.crt


