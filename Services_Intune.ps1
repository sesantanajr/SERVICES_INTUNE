# Caminho para salvar o log de execução
$logPath = "$PSScriptRoot\ServiceManagementLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Lista de serviços críticos a serem gerenciados
$criticalServices = @(
    "winmgmt",               # Serviço de Instrumentação de Gerenciamento do Windows
    "wuauserv",              # Serviço de Windows Update
    "dmwappushservice",      # Serviço de Mensagens para o MDM
    "BITS",                  # Serviço de Transferência Inteligente em Segundo Plano
    "cryptsvc",              # Serviço de Criptografia
    "UsoSvc",                # Serviço de Orquestração de Atualizações
    "DeviceInstall",         # Serviço de Instalação de Dispositivos
    "TrustedInstaller"       # Instalador de Módulos do Windows
)

# Lista de serviços de rede protegidos
$networkServices = @(
    "Netman", "Dhcp", "NlaSvc", "WlanSvc", "WWANAutoConfig", "iphlpsvc", "netprofm", "Dnscache"
)

# Função para registrar logs
function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "INFO" # INFO, WARN, ERROR
    )
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Type] $Message"
    Write-Host $logEntry
    Add-Content -Path $logPath -Value $logEntry
}

# Função para reparar o sistema
function Repair-System {
    Write-Log "Iniciando o reparo do sistema com SFC e DISM."

    # Executando SFC
    Write-Log "Executando SFC /scannow..."
    try {
        sfc /scannow | Out-Null
        Write-Log "SFC executado com sucesso."
    } catch {
        Write-Log "Erro ao executar SFC: $($_)" -Type "ERROR"
    }

    # Executando DISM
    Write-Log "Executando DISM /online /cleanup-image /scanhealth..."
    try {
        dism /online /cleanup-image /scanhealth | Out-Null
        $healthStatus = (dism /online /cleanup-image /checkhealth | Out-String)
        if ($healthStatus -match "can be repaired") {
            Write-Log "Restaurando imagem do sistema com DISM /restorehealth..."
            dism /online /cleanup-image /restorehealth | Out-Null
            Write-Log "Imagem do sistema restaurada com sucesso."
        } else {
            Write-Log "A imagem do sistema está íntegra. Nenhuma ação necessária."
        }
    } catch {
        Write-Log "Erro ao executar DISM: $($_)" -Type "ERROR"
    }
}

# Função para reiniciar serviços críticos
function Restart-CriticalServices {
    param (
        [string[]]$ServiceList
    )

    foreach ($service in $ServiceList) {
        try {
            $serviceStatus = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($null -eq $serviceStatus) {
                Write-Log "Serviço $service não encontrado." -Type "WARN"
                continue
            }

            # Tenta reiniciar o serviço
            if ($serviceStatus.Status -eq "Running") {
                Write-Log "Reiniciando o serviço ${service}..."
                Stop-Service -Name $service -Force -ErrorAction Stop
            }

            Start-Service -Name $service -ErrorAction Stop
            Write-Log "Serviço ${service} reiniciado com sucesso."
        } catch {
            Write-Log "Erro ao reiniciar o serviço ${service}: $($_)" -Type "ERROR"
        }
    }
}

# Função para verificar e iniciar serviços de rede
function Ensure-NetworkServicesRunning {
    Write-Log "Verificando os serviços de rede críticos..."

    foreach ($service in $networkServices) {
        try {
            $serviceStatus = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($null -eq $serviceStatus) {
                Write-Log "Serviço ${service} não encontrado." -Type "WARN"
                continue
            }

            if ($serviceStatus.Status -eq "Stopped") {
                Write-Log "Serviço ${service} está parado. Iniciando..."
                Start-Service -Name $service -ErrorAction Stop
                Write-Log "Serviço ${service} iniciado com sucesso."
            } else {
                Write-Log "Serviço ${service} já está em execução. Nenhuma ação necessária."
            }
        } catch {
            Write-Log "Erro ao verificar ou iniciar o serviço ${service}: $($_)" -Type "ERROR"
        }
    }
}

# Função para sincronizar com o Intune
function Sync-WithIntune {
    Write-Log "Forçando sincronização com o Intune..."
    try {
        Invoke-Expression "C:\Windows\System32\dsregcmd.exe /refreshpr"
        Write-Log "Sincronização com o Intune forçada com sucesso."
    } catch {
        Write-Log "Erro ao sincronizar com o Intune: $($_)" -Type "ERROR"
    }
}

# Executa as funções principais
Write-Log "Iniciando a execução do script de gerenciamento de serviços."

Repair-System
Ensure-NetworkServicesRunning
Restart-CriticalServices -ServiceList $criticalServices
gpupdate /force
Sync-WithIntune

Write-Log "Script concluído! Logs salvos em: $logPath"
