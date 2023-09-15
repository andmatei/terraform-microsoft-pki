# Download AWS CLI installer
Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "AWSCLIV2.msi"

# Install AWS CLI
Start-Process msiexec.exe -Wait -ArgumentList '/i AWSCLIV2.msi /quiet'

# Download AWS CloudHSM CLI installer
Invoke-WebRequest -Uri 'https://s3.amazonaws.com/cloudhsmv2-software/CloudHsmClient/Windows/AWSCloudHSMCLI-latest.msi' -OutFile 'C:\AWSCloudHSMCLI-latest.msi'

# Install AWS CloudHSM CLI
Start-Process msiexec.exe -ArgumentList '/i C:\AWSCloudHSMCLI-latest.msi /quiet /norestart /log C:\client-install.txt' -Wait

# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# Install OpenSSL
choco install openssl.light -y

# Refresh environment
Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
refreshenv

# Create a new directory
New-Item -Path "C:\HSM" -ItemType Directory -Force

# Change to the new directory
Set-Location -Path "C:\HSM"

# Get cluster CSR
# aws cloudhsmv2 describe-clusters --filters clusterIds="${cluster_id}" --output text --query "Clusters[].Certificates.ClusterCsr" | Out-File -FilePath ".\clusterCSR.csr" -Encoding utf8
$cluster = Get-HSM2Cluster -Filter @{clusterIds = "${cluster_id}"} 

if ($cluster.State -eq "UNINITIALIZED") {
    $csr = $cluster.Certificates.ClusterCsr
    $csr | Out-File -FilePath ".\clusterCSR.csr" -Encoding utf8

    # Create private key
    openssl genrsa -out customerCA.key 2048

    # Create self-signed certificate
    openssl req -new -x509 -days 3652 -key customerCA.key -out customerCA.crt -subj "/C=US/ST=State/L=City/O=Organization/OU=Organizational Unit/CN=Common Name"

    # Sign the cluster CSR
    openssl x509 -req -days 3652 -in clusterCSR.csr -CA customerCA.crt -CAkey customerCA.key  -CAcreateserial -out customerHsmCertificate.crt

    # Initialize cluster
    Initialize-HSM2Cluster -ClusterId "${cluster_id}" -SignedCert (Get-Content .\customerHsmCertificate.crt -Raw) -TrustAnchor (Get-Content .\customerCA.crt -Raw)
}

$desired_state = "INITIALIZED"
$max_retries = 20
$retry_interval_seconds = 30

function Get-ClusterState {
    $cluster = Get-HSM2Cluster -Filter @{clusterIds = "${cluster_id}"}
    return $cluster.State
}

for ($retry_count = 1; $retry_count -le $max_retries; $retry_count++) {
    $clusterState = Get-ClusterState

    if ($clusterState -eq $desired_state) {
        Write-Host "Cluster is in the desired state: $desired_state"
        break
    }

    Write-Host "Cluster is in state: $clusterState. Retrying in $retry_interval_seconds seconds..."
    Start-Sleep -Seconds $retry_interval_seconds
}

if ($retry_count -gt $max_retries) {
    Write-Host "Timeout: Unable to reach the desired state within the specified retries."
    throw
}

$cluster = Get-HSM2Cluster -Filter @{clusterIds = "${cluster_id}"}
$eniIP = $cluster.Hsms.EniIp

Copy-Item -Path .\customerCA.crt -Destination "C:\ProgramData\Amazon\CloudHSM\customerCA.crt"

Set-Location -Path "C:\Program Files\Amazon\CloudHSM\bin"
.\configure-cli.exe -a $eniIP

# HERE
.\cloudhsm-cli.exe cluster activate --password <PASSWORD>
Set-Item -Path "env:CLOUDHSM_ROLE" -Value "admin"
Set-Item -Path "env:CLOUDHSM_PIN" -Value "admin:<PASSWORD>"
.\cloudhsm-cli.exe user create --username <USERNAME> --role crypto-user --password <OTHER_PASSWORD>

