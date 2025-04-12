#!/bin/bash

# Requer sudo
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root: sudo ./setup.sh"
  exit
fi

# 📩 Solicita e-mail e senha
read -p "Digite seu e-mail do Parsec: " PARSEC_EMAIL
read -s -p "Digite sua senha do Parsec: " PARSEC_PASSWORD
echo

# 🧠 RAM personalizada
read -p "Quanto de RAM deseja alocar para o Windows (GB)? [Padrão: 10] " RAM_INPUT
RAM_INPUT=${RAM_INPUT:-10}
if [[ "$RAM_INPUT" -gt 12 ]]; then
  echo "⚠️  Máximo permitido é 12 GB. Usando 12."
  RAM_INPUT=12
fi
RAM_SIZE="${RAM_INPUT}G"

# 🧠 CPU personalizada
read -p "Quantos núcleos de CPU deseja alocar? [Padrão: 4] " CPU_INPUT
CPU_INPUT=${CPU_INPUT:-4}
if [[ "$CPU_INPUT" -gt 4 ]]; then
  echo "⚠️  Máximo permitido são 4 núcleos. Usando 4."
  CPU_INPUT=4
fi
CPU_CORES="$CPU_INPUT"

# Instala Docker e Compose
apt update && apt install -y docker.io docker-compose
systemctl start docker
systemctl enable docker

# Cria estrutura
mkdir -p ~/dockercom/scripts
cd ~/dockercom

# Cria docker-compose com RAM e CPU personalizados
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

# Verifica se é a primeira execução
if [ ! -f "/parsecsetup/first_run.flag" ]; then
  echo "Primeira execução detectada. Realizando configurações iniciais..."

  # Script PowerShell que agenda o script principal no login
  cat <<EOF > scripts/parsec_setup.ps1
\$taskName = "ParsecAutoLogin"
\$task = schtasks /Query /TN \$taskName 2>&1
if (\$task -like "*ERROR*") {
    \$script = "C:\\parsecsetup\\parsec_run.ps1"
    schtasks /Create /TN \$taskName /TR "powershell -ExecutionPolicy Bypass -File \$script" /SC ONLOGON /RL HIGHEST /F /RU MASTER
}
EOF

  # Script PowerShell principal que instala Parsec e faz login
  cat <<EOF > scripts/parsec_run.ps1
Invoke-WebRequest -Uri "https://builds.parsec.app/package/parsec-windows.exe" -OutFile "C:\\Users\\MASTER\\Downloads\\parsec.exe"
Start-Process "C:\\Users\\MASTER\\Downloads\\parsec.exe" -ArgumentList "/S" -Wait
Start-Sleep -Seconds 10
Start-Process "C:\\Program Files\\Parsec\\parsec.exe"
Start-Sleep -Seconds 8
Start-Process "C:\\Program Files\\Parsec\\parsec.exe" -ArgumentList "login $PARSEC_EMAIL $PARSEC_PASSWORD"
Write-Host "✅ Parsec instalado e login enviado. Confirme o e-mail de localização se solicitado."
EOF

  # Limpar todos os aplicativos de startup, exceto Parsec
  Write-Host "Removendo aplicativos de startup..."

  # Desabilita todos os itens de startup
  \$startupFolder = [System.Environment]::GetFolderPath("Startup")
  \$startupItems = Get-ChildItem -Path \$startupFolder
  foreach (\$item in \$startupItems) {
      Remove-Item \$item.FullName -Force
  }

  # Remover outras entradas do registro (se houver)
  $regPaths = @(
      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
      "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
  )

  foreach ($regPath in $regPaths) {
      $items = Get-ItemProperty -Path $regPath
      foreach ($item in $items.PSObject.Properties) {
          if ($item.Name -ne "Parsec") {
              Remove-ItemProperty -Path $regPath -Name $item.Name -Force
          }
      }
  }

  Write-Host "✅ Todos os itens de startup removidos, exceto Parsec."

  # Criar o arquivo de flag para marcar que já foi a primeira execução
  touch /parsecsetup/first_run.flag

  # Reiniciar a máquina automaticamente
  Write-Host "Reiniciando a máquina..."
  Restart-Computer -Force
fi

# Sobe o container
docker-compose -f windows10.yml up -d

# Fim
echo
echo "✅ Container Windows criado com:"
echo "   🧠 RAM: $RAM_SIZE"
echo "   ⚙️  Núcleos: $CPU_CORES"
echo "✅ Parsec instalado e login agendado para rodar automaticamente"
echo "✅ A máquina será reiniciada automaticamente após a configuração"
echo "📡 Conecte via Parsec para começar a usar"
echo "👤 Usuário: MASTER | Senha: admin@123"
echo "📁 Scripts acessíveis em: C:\\parsecsetup"
echo
