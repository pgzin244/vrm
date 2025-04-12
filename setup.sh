#!/bin/bash

# Pergunta o e-mail e senha do Parsec (só vai pedir uma vez)
if [ ! -f "$HOME/.parsec_credentials" ]; then
    echo "Digite seu e-mail do Parsec:"
    read PARSEC_EMAIL
    echo "Digite sua senha do Parsec:"
    read -s PARSEC_PASSWORD
    echo "$PARSEC_EMAIL" > "$HOME/.parsec_credentials"
    echo "$PARSEC_PASSWORD" >> "$HOME/.parsec_credentials"
else
    PARSEC_EMAIL=$(sed -n '1p' "$HOME/.parsec_credentials")
    PARSEC_PASSWORD=$(sed -n '2p' "$HOME/.parsec_credentials")
fi

# Pergunta a quantidade de RAM
echo "Quanto de RAM deseja alocar para o Windows (GB)? [Padrão: 10]"
read RAM_INPUT
RAM_INPUT=${RAM_INPUT:-10}
if [[ "$RAM_INPUT" -gt 12 ]]; then
    echo "⚠️ Máximo é 12 GB. Usando 12."
    RAM_INPUT=12
fi
RAM_SIZE="${RAM_INPUT}G"

# Pergunta a quantidade de núcleos de CPU
echo "Quantos núcleos de CPU deseja alocar? [Padrão: 4]"
read CPU_INPUT
CPU_INPUT=${CPU_INPUT:-4}
if [[ "$CPU_INPUT" -gt 4 ]]; then
    echo "⚠️ Máximo são 4 núcleos. Usando 4."
    CPU_INPUT=4
fi
CPU_CORES="$CPU_INPUT"

# Instalar Docker e Docker Compose
sudo apt update
sudo apt install -y docker.io docker-compose

# Criar o arquivo docker-compose.yml
echo "Criando o arquivo docker-compose.yml..."
cat <<EOF > docker-compose.yml
version: '3.7'

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
    stop_grace_period: 2m
EOF

# Iniciar o Docker Compose
echo "Iniciando a VM do Windows..."
sudo docker-compose up -d

# Instalar o Parsec na VM
echo "Instalando o Parsec na VM do Windows..."
sudo docker exec -it windows powershell -Command "
    Invoke-WebRequest -Uri 'https://builds.parsec.app/package/parsec-windows.exe' -OutFile 'C:\\\\Users\\\\MASTER\\\\Downloads\\\\parsec.exe'
    Start-Process 'C:\\\\Users\\\\MASTER\\\\Downloads\\\\parsec.exe' -ArgumentList '/S' -Wait
    Start-Sleep -Seconds 10
    Start-Process 'C:\\\\Program Files\\\\Parsec\\\\parsec.exe'
"

# Aguardar a verificação de email do Parsec (simulando aqui)
echo "Aguardando verificação de email do Parsec..."
sleep 15  # Simulação de espera para o usuário realizar a verificação

# Fazer login no Parsec
echo "Fazendo login no Parsec..."
sudo docker exec -it windows powershell -Command "
    Start-Process 'C:\\\\Program Files\\\\Parsec\\\\parsec.exe' -ArgumentList 'login $PARSEC_EMAIL $PARSEC_PASSWORD'
"

# Configurar o Parsec para alto desempenho
echo "Configurando o Parsec para alto desempenho..."
sudo docker exec -it windows powershell -Command "
    Start-Process -FilePath 'C:\\\\Program Files\\\\Parsec\\\\parsec.exe' -ArgumentList 'settings -fps 60 -quality ultra -audio-quality high -disable-vsync true'
"

# Desabilitar apps de startup (exceto Parsec)
echo "Desabilitando apps de startup (exceto o Parsec)..."
sudo docker exec -it windows powershell -Command "
    Get-CimInstance -ClassName Win32_StartupCommand | Where-Object { \$_ .Command -notlike '*parsec*' } | ForEach-Object {
        \$_ .Disable()
    }
"

# Reiniciar a VM do Windows
echo "Reiniciando a VM..."
sudo docker exec -it windows powershell -Command "Restart-Computer -Force"

echo "✅ Ambiente Windows configurado com sucesso!"
