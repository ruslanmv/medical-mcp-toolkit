# install_docker.ps1 — for Windows 10/11
# Checks and installs Docker Desktop if missing
# Ensures Docker Compose v2 is available

Write-Host "🔧 Verifica presenza di Docker Desktop..."

# Check if Docker is already installed
$dockerExists = Get-Command docker -ErrorAction SilentlyContinue
$composeWorks = docker compose version -ErrorAction SilentlyContinue

if ($dockerExists -and $composeWorks) {
    Write-Host "✅ Docker e Docker Compose v2 sono già installati e funzionanti."
    docker --version
    docker compose version
    exit 0
}

Write-Host "`n❗ Docker Desktop non rilevato o incompleto."
Write-Host "➡️  Sarà scaricato e installato Docker Desktop."

# Download Docker Desktop installer
$installerUrl = "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
$installerPath = "$env:TEMP\DockerInstaller.exe"

Write-Host "⬇️  Download da: $installerUrl"
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

# Install Docker Desktop silently
Write-Host "⚙️  Avvio installazione silenziosa..."
Start-Process -FilePath $installerPath -ArgumentList "install", "--quiet" -Wait

# Cleanup installer
Remove-Item $installerPath

# Add user to docker-users group (may require reboot)
$CurrentUser = "$env:USERDOMAIN\$env:USERNAME"
Write-Host "👥 Aggiunta di $CurrentUser al gruppo 'docker-users'..."
net localgroup docker-users $CurrentUser /add

Write-Host "`n🔄 Riavvio dei servizi Docker (se necessario)..."
Start-Sleep -Seconds 5

# Prompt reboot
Write-Host "`n⚠️  Per completare la configurazione, potrebbe essere necessario RIAVVIARE il computer."
Write-Host "➡️  Dopo il riavvio, verifica il funzionamento con:"
Write-Host "    docker --version"
Write-Host "    docker compose version"

Write-Host "`n🎉 Docker Desktop è stato installato!"
