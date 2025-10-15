# scripts/windows/install_python_win.ps1
# Installa Python 3.11 su Windows usando il Python Launcher (py)

param(
    [string]$InstallRoot = $PWD,         # opzionale; non usato ma accettato dal dispatcher
    [string]$Version     = "3.11.4"      # versione di Python da installare
)

Write-Host "`n🔧 Controllo presenza di Python 3.11..."

function Test-PyLauncher {
    try { Get-Command py -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Test-Py311 {
    if (-not (Test-PyLauncher)) { return $false }
    try { & py -3.11 -c "import sys" *> $null; return $true } catch { return $false }
}

if (Test-Py311) {
    Write-Host "✅ Python 3.11 è già installato:"
    & py -3.11 --version
    exit 0
}

Write-Host "🚀 Python 3.11 non trovato. Avvio installazione..."

# Imposta URL e percorso di installazione (64-bit per default)
$arch          = "amd64"
$installerUrl  = "https://www.python.org/ftp/python/$Version/python-$Version-$arch.exe"
$installerPath = Join-Path $env:TEMP "python-$Version-installer.exe"

# Garantisce TLS 1.2 su PowerShell 5.x
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Scarica l’installer
Write-Host "⬇️  Download di Python $Version da python.org..."
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

# Installa Python in modo silenzioso con pip e aggiunta al PATH (include anche il launcher 'py')
$arguments = "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 Include_launcher=1"
Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait

# Elimina installer
Remove-Item $installerPath -ErrorAction SilentlyContinue

# Verifica installazione
if (-not (Test-Py311)) {
    Write-Host "❌ Errore: Python 3.11 non si è installato correttamente."
    exit 1
}

# Upgrade pip e pacchetti base
Write-Host "📦 Aggiornamento pip, setuptools e wheel..."
& py -3.11 -m pip install --upgrade pip setuptools wheel

Write-Host "`n✅ Python 3.11 installato con successo!"
& py -3.11 --version

Write-Host "`n🔧 Consigli:"
Write-Host "• Per creare un ambiente virtuale:"
Write-Host "    py -3.11 -m venv venv"
Write-Host "• Per attivarlo:"
Write-Host "    .\venv\Scripts\Activate.ps1"
Write-Host "`n🎉 Python è pronto all’uso!"
