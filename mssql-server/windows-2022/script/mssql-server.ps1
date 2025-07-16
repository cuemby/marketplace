# Ejecutar este script como Administrador

# ===========================
# CONFIGURACIÓN
# ===========================
$SqlInstallerUrl = "https://aka.ms/SQLServer2019-Dev"
$InstallerPath = "C:\Temp\SQL2019.exe"
$SaPassword = ""
$SqlInstance = "MSSQLSERVER"
$Port = 1433

# Crear carpeta si no existe
if (-Not (Test-Path -Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp"
}

Write-Host "🔽 Descargando instalador de SQL Server..."
Invoke-WebRequest -Uri $SqlInstallerUrl -OutFile $InstallerPath

Write-Host "💾 Instalando SQL Server silenciosamente..."
Start-Process -FilePath $InstallerPath -ArgumentList "/Q /ACTION=Install /FEATURES=SQLEngine /INSTANCENAME=$SqlInstance /SECURITYMODE=SQL /SAPWD=$SaPassword /TCPENABLED=1 /IACCEPTSQLSERVERLICENSETERMS" -Wait

Write-Host "✅ Instalación completada."

# ===========================
# HABILITAR TCP/IP
# ===========================
Write-Host "🌐 Habilitando TCP/IP..."
Import-Module "SQLPS" -DisableNameChecking

$wmi = new-object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') .
$serverProtocol = $wmi.ServerInstances[$SqlInstance].ServerProtocols["Tcp"]

if ($serverProtocol.IsEnabled -eq $false) {
    $serverProtocol.IsEnabled = $true
    $serverProtocol.Alter()
}

# Configurar puerto
$ipAll = $serverProtocol.IPAddresses["IPAll"]
$ipAll.IPAddressProperties["TcpDynamicPorts"].Value = ""
$ipAll.IPAddressProperties["TcpPort"].Value = "$Port"
$serverProtocol.Alter()

# Reiniciar servicio
Write-Host "🔄 Reiniciando servicio SQL Server..."
Restart-Service -Name "MSSQLSERVER"

# ===========================
# CONFIGURAR FIREWALL
# ===========================
Write-Host "🛡️ Configurando firewall..."
New-NetFirewallRule -DisplayName "SQL Server TCP $Port" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow

Write-Host "✅ SQL Server 2019 instalado y configurado correctamente."
Write-Host ""
Write-Host "ℹ️ Puedes conectarte con:"
Write-Host "   sqlcmd -S localhost,$Port -U sa -P '$SaPassword'"
