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

# Add OpenSSL to the system's PATH
$opensslPath = "C:\Program Files\OpenSSL\bin"
[Environment]::SetEnvironmentVariable("Path", "$opensslPath", [System.EnvironmentVariableTarget]::Machine)

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Create a new directory
New-Item -Path "C:\Test" -ItemType Directory -Force

# Change to the new directory
Set-Location -Path "C:\Test"

openssl genrsa  -out customerCA.key 2048

# Create a new directory
New-Item -Path "C:\HSM" -ItemType Directory -Force

# Change to the new directory
Set-Location -Path "C:\HSM"

# Get cluster CSR
# aws cloudhsmv2 describe-clusters --filters clusterIds="${cluster_id}" --output text --query "Clusters[].Certificates.ClusterCsr" | Out-File -FilePath ".\clusterCSR.csr" -Encoding utf8
# Define the name of the AWS Tools for PowerShell module
$moduleName = 'AWSPowerShell'

# Check if the module is installed
$installedModules = Get-Module -ListAvailable | Where-Object { $_.Name -eq $moduleName }

if ($installedModules) {
    Write-Host "AWS Tools for PowerShell module ('$moduleName') is installed."

    $importedModules = Get-Module -Name $moduleName -List

    if ($importedModules) {
        Write-Host "Module '$moduleName' is imported in the current session."

        $cluster = Get-HSM2Cluster -Filter @{clusterIds = "${cluster_id}"}
        $cluster.ClusterId | Out-File -FilePath ".\test.txt"
    } else {
        Write-Host "Module '$moduleName' is not imported in the current session."
    }
} else {
    Write-Host "AWS Tools for PowerShell module ('$moduleName') is not installed."
}

# if ($cluster.State -eq "UNINITIALIZED") {
    # $csr = $cluster.Certificates.ClusterCsr
    # $csr | Out-File -FilePath ".\clusterCSR.csr" -Encoding utf8

    # # Create private key
    # openssl genrsa  -out customerCA.key 2048

    # # Create self-signed certificate
    # openssl req -new -x509 -days 3652 -key customerCA.key -out customerCA.crt -subj "/C=US/ST=State/L=City/O=Organization/OU=Organizational Unit/CN=Common Name"

    # # Sign the cluster CSR
    # openssl x509 -req -days 3652 -in clusterCSR.csr -CA customerCA.crt -CAkey customerCA.key  -CAcreateserial -out customerHsmCertificate.crt

    # Initialize cluster
    # Initialize-HSM2Cluster -ClusterId "${cluster_id}" -SignedCert (Get-Content .\customerHsmCertificate.crt) -TrustAnchor (Get-Content .\customerCA.crt)
# }

