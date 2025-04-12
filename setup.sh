#!/bin/bash

LOG_FILE="setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
  echo "🚫 Por favor, execute como root: sudo ./setup.sh"
  exit 1
fi

echo "🔧 Iniciando configuração do ambiente..."

# Solicita Parsec (seguro, com arquivo temporário)
read -p "Digite seu e-mail do Parsec: " PARSEC_EMAIL
read -s -p "Digite sua senha do Parsec: " PARSEC_PASSWORD
echo

TMP_SECRET_FILE="/tmp/parsec.secret"
echo "$PARSEC_EMAIL" > "$TMP_SECRET_FILE"
echo "$PARSEC_PASSWORD" >> "$TMP_SECRET_FILE"

# Entrada de RAM com validação
read -p "Quanto de RAM deseja alocar para o Windows (GB)? [Padrão: 10] " RAM_INPUT
RAM_INPUT=${RAM_INPUT:-10}
if ! [[ "$RAM_INPUT" =~ ^[0-9]+$ ]]; then
  echo "❌ Valor inválido. Usando 10 GB."
  RAM_INPUT=10
fi
if [[ "$RAM_INPUT" -gt 12 ]]; then
  echo "⚠️ Máximo permitido é 12 GB. Usando 12."
  RAM_INPUT=12
fi
RAM_SIZE="${RAM_INPUT}G"

# Entrada de CPU com validação
read -p "Quantos núcleos de CPU deseja alocar? [Padrão: 4] " CPU_INPUT
CPU_INPUT=${CPU_INPUT:-4}
if ! [[ "$CPU_INPUT" =~ ^[0-9]+$ ]]; then
  echo "❌ Valor inválido. Usando 4 núcleos."
  CPU_INPUT=4
fi
if [[ "$CPU_INPUT" -gt 4 ]]; then
  echo "⚠️ Máximo permitido são 4 núcleos. Usando 4."
  CPU_INPUT=4
fi
CPU_CORES="$CPU_INPUT"

# Instala Docker e Compose
echo "📦 Instalando Docker e Docker Compose..."
apt update && apt install -y docker.io docker-compose

systemctl start docker
systemctl enable docker

# Estrutura de diretórios
mkdir -p ~/dockercom/scripts
cd ~/dockercom || exit 1

# Se o container já existir, evita recriação
if docker ps -a --format '{{.Names}}' | grep -q "^windows$"; then
  echo "⚠️ Container 'windows' já existe. Pulando criação."
else
  # Criação do docker-compose com os parâmetros
  echo "📝 Gerando arquivo docker-compose..."

  cat <<EOF > windows10.yml
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "10"
      USERNAME: "MASTER"
      PASSWORD: "admin@123"
      RAM_SIZE: "$RAM_SIZE"
      CPU_CORES: "$CPU_CORES"
      DISK_SIZE: "400G"
      DISK2_SIZE: "100G"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - ./scripts:/parsecsetup
    stop_grace_period: 2m
EOF

  # Verifica se é primeira execução
  if [ ! -f "scripts/first_run.flag" ]; then
    echo "🛠️ Primeira execução detectada. Criando scripts PowerShell..."

    EMAIL=$(head -n 1 "$TMP_SECRET_FILE")
    PASSWORD=$(tail -n 1 "$TMP_SECRET_FILE")

    cat <<EOF > scripts/parsec_setup.ps1
\$taskName = "ParsecAutoLogin"
\$task = schtasks /Query /TN \$taskName 2>&1
if (\$task -like "*ERROR*") {
    \$script = "C:\\\\parsecsetup\\\\parsec_run.ps1"
    schtasks /Create /TN \$taskName /TR "powershell -ExecutionPolicy Bypass -File \$script" /SC ONLOGON /RL HIGHEST /F /RU MASTER
}
EOF

    cat <<EOF > scripts/parsec_run.ps1
Invoke-WebRequest -Uri "https://builds.parsec.app/package/parsec-windows.exe" -OutFile "C:\\\\Users\\\\MASTER\\\\Downloads\\\\parsec.exe"
Start-Process "C:\\\\Users\\\\MASTER\\\\Downloads\\\\parsec.exe" -ArgumentList "/S" -Wait
Start-Sleep -Seconds 10
Start-Process "C:\\\\Program Files\\\\Parsec\\\\parsec.exe"
Start-Sleep -Seconds 8
Start-Process "C:\\\\Program Files\\\\Parsec\\\\parsec.exe" -ArgumentList "login $EMAIL $PASSWORD"
Write-Host "✅ Parsec instalado e login enviado. Confirme o e-mail se solicitado."
EOF

    cat <<EOF > scripts/clear_startup.ps1
\$startupFolder = [System.Environment]::GetFolderPath("Startup")
\$startupItems = Get-ChildItem -Path \$startupFolder
foreach (\$item in \$startupItems) {
    Remove-Item \$item.FullName -Force
}

\$regPaths = @(
  "HKCU:\\\\Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run",
  "HKLM:\\\\Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run"
)

foreach (\$regPath in \$regPaths) {
  \$items = Get-ItemProperty -Path \$regPath
  foreach (\$item in \$items.PSObject.Properties) {
    if (\$item.Name -ne "Parsec") {
      Remove-ItemProperty -Path \$regPath -Name \$item.Name -Force
    }
  }
}
EOF

    touch scripts/first_run.flag
    echo "♻️ Reiniciando sistema para aplicar as configurações..."
    systemctl reboot
  fi
fi

# Sobe o container (caso ainda não esteja rodando)
if ! docker ps --format '{{.Names}}' | grep -q "^windows$"; then
  echo "🚀 Subindo container Windows..."
  docker-compose -f windows10.yml up -d
else
  echo "ℹ️ Container 'windows' já está rodando."
fi

# Limpa arquivos temporários
rm -f "$TMP_SECRET_FILE"

# Mensagem final
echo
echo "✅ Ambiente Windows criado com sucesso:"
echo "   🧠 RAM: $RAM_SIZE"
echo "   ⚙️  CPU: $CPU_CORES núcleos"
echo "👤 Usuário: MASTER | Senha: admin@123"
echo "📁 Scripts disponíveis em C:\\parsecsetup"
echo "📡 Acesse via Parsec após o boot"
echo "📝 Log disponível em: $(realpath $LOG_FILE)"
