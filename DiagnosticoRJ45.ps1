<#
.SYNOPSIS
    Diagnóstico RJ45 1.2.0 — diagnóstico do ponto de rede Ethernet conectado (versão PowerShell portátil).

.DESCRIPTION
    Um único script, sem instalação. Usa somente componentes que já fazem parte do Windows 10/11:
    Windows PowerShell 5.1, módulos NetAdapter/NetTCPIP/DnsClient, WMI/CIM, ping.exe e o log de eventos.
    Não compila código (sem Add-Type de código-fonte), não grava logs, configurações ou arquivos auxiliares.
    Os resultados ficam em memória; o relatório só é gravado quando o usuário escolhe "Salvar relatório".
    Não pede elevação e não altera configurações de rede ou de segurança.

    Parâmetros de verificação (sem interface gráfica):
      -UnitTest  verificações de interpretação que não dependem de hardware (rodam até fora do Windows).
      -SelfTest  verificações de interpretação + rota/ICMP de loopback + inventário em texto (somente Windows).

.NOTES
    Licença: Unlicense (domínio público). https://github.com/gustavosantos21/diagnostico-rj45
#>
[CmdletBinding()]
param(
    [switch]$UnitTest,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$script:AppVersion = '1.2.0'
$script:PingExe = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32\PING.EXE' } else { 'ping' }

# ---------------------------------------------------------------------------------------------
# Funções de interpretação (sem dependência de hardware; cobertas por -UnitTest)
# ---------------------------------------------------------------------------------------------

function Test-HasText([object]$Value) {
    return ($null -ne $Value) -and ("$Value".Trim().Length -gt 0)
}

function Format-Value([object]$Value) {
    if ($Value -is [System.Array]) { $Value = (@($Value) | Where-Object { Test-HasText $_ }) -join ', ' }
    if (Test-HasText $Value) { return "$Value" }
    return 'não disponível'
}

function Format-Speed([double]$Bits) {
    if ($Bits -le 0 -or $Bits -ge 9e18) { return 'indisponível' }
    if ($Bits -ge 1e9) { return ('{0:0.##} Gb/s' -f ($Bits / 1e9)) }
    return ('{0:0.##} Mb/s' -f ($Bits / 1e6))
}

function ConvertTo-IPv4Mask([int]$PrefixLength) {
    if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) { return '' }
    [uint32]$bits = 0
    if ($PrefixLength -gt 0) { $bits = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $PrefixLength)) }
    $bytes = [BitConverter]::GetBytes($bits)
    [array]::Reverse($bytes)
    return ($bytes -join '.')
}

function Get-FirstIPAddress([string]$Text) {
    if (-not $Text) { return $null }
    $v4 = [regex]::Match($Text, '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])')
    if ($v4.Success) { return $v4.Value }
    $v6 = [regex]::Match($Text, '(?<![0-9A-Fa-f:])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?:%[0-9A-Za-z]+)?')
    if ($v6.Success) {
        $candidate = $v6.Value.TrimEnd(':')
        $parsed = $null
        if ([System.Net.IPAddress]::TryParse(($candidate -split '%')[0], [ref]$parsed)) { return $candidate }
    }
    return $null
}

function Test-SameIPAddress([string]$A, [string]$B) {
    $x = $null; $y = $null
    if (-not (Test-HasText $A) -or -not (Test-HasText $B)) { return $false }
    if (-not [System.Net.IPAddress]::TryParse(($A -split '%')[0], [ref]$x)) { return $false }
    if (-not [System.Net.IPAddress]::TryParse(($B -split '%')[0], [ref]$y)) { return $false }
    return ([BitConverter]::ToString($x.GetAddressBytes()) -eq [BitConverter]::ToString($y.GetAddressBytes()))
}

function Test-IPv4Text([string]$Text) {
    $p = $null
    return ([System.Net.IPAddress]::TryParse("$Text", [ref]$p) -and $p.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork)
}

function Test-IPv6Text([string]$Text) {
    $p = $null
    return ([System.Net.IPAddress]::TryParse((("$Text") -split '%')[0], [ref]$p) -and $p.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6)
}

# Interpreta a saída de "ping -n 1" em qualquer idioma do Windows.
# Kind: reply (resposta do destino), hop (resposta de outro equipamento, ex.: TTL expirado),
#       local (erro gerado pelo próprio computador, ex.: host inacessível), noreply (sem resposta),
#       error (falha do comando ou resposta do destino sem tempo de ida e volta).
function ConvertFrom-PingOutput([string[]]$Lines, [string]$Target, [string]$Source) {
    $result = [pscustomobject]@{ Kind = 'noreply'; Latency = $null; LessThanOne = $false; Responder = $null; Message = '' }
    $clean = @($Lines | ForEach-Object { "$_".Trim() } | Where-Object { $_.Length -gt 0 })
    if ($clean.Count -lt 2) {
        $result.Kind = 'error'
        $result.Message = ($clean -join ' ')
        return $result
    }
    $line = $clean[1]
    $result.Message = $line
    $ip = Get-FirstIPAddress $line
    if (-not $ip) { return $result }

    $result.Responder = ($ip -split '%')[0]
    $position = $line.IndexOf($ip)
    if ($position -ge 0) {
        $tail = $line.Substring($position + $ip.Length).TrimStart(':', ' ')
        if ($tail) { $result.Message = $tail }
    }
    $time = [regex]::Match($line, '([=<])\s*(\d+)\s*ms', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (Test-SameIPAddress $ip $Target) {
        if ($time.Success) {
            $result.Kind = 'reply'
            $result.LessThanOne = ($time.Groups[1].Value -eq '<')
            $result.Latency = if ($result.LessThanOne) { 0 } else { [int]$time.Groups[2].Value }
        } else {
            $result.Kind = 'error'
        }
    } elseif ((Test-HasText $Source) -and (Test-SameIPAddress $ip $Source)) {
        $result.Kind = 'local'
    } else {
        $result.Kind = 'hop'
    }
    return $result
}

function Format-Latency($PingResult) {
    if ($PingResult.LessThanOne) { return '<1 ms' }
    return "$($PingResult.Latency) ms"
}

function Get-MacInfo([string]$Mac) {
    $hex = ("$Mac" -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($hex.Length -ne 12 -or $hex -eq '000000000000') { return 'não disponível' }
    $oui = '{0}-{1}-{2}' -f $hex.Substring(0, 2), $hex.Substring(2, 2), $hex.Substring(4, 2)
    $first = [Convert]::ToByte($hex.Substring(0, 2), 16)
    $notes = @("prefixo OUI $oui")
    if ($hex.StartsWith('00000C07AC')) { $notes += 'MAC virtual HSRP v1 (Cisco), grupo ' + [Convert]::ToInt32($hex.Substring(10, 2), 16) }
    elseif ($hex.StartsWith('00000C9FF')) { $notes += 'MAC virtual HSRP v2 (Cisco), grupo ' + [Convert]::ToInt32($hex.Substring(9, 3), 16) }
    elseif ($hex.StartsWith('00005E0001')) { $notes += 'MAC virtual VRRP (IPv4), VRID ' + [Convert]::ToInt32($hex.Substring(10, 2), 16) }
    elseif ($hex.StartsWith('00005E0002')) { $notes += 'MAC virtual VRRP (IPv6), VRID ' + [Convert]::ToInt32($hex.Substring(10, 2), 16) }
    elseif ($hex.StartsWith('0007B400')) { $notes += 'MAC virtual GLBP (Cisco)' }
    elseif (($first -band 2) -ne 0) { $notes += 'endereço administrado localmente (virtual ou aleatório; o prefixo não identifica fabricante)' }
    else { $notes += 'consulte o fabricante desse prefixo no registro público da IEEE' }
    return ($notes -join '; ')
}

function Get-PrimaryIPv4($Adapter) {
    $all = @($Adapter.IPv4 | Where-Object { Test-HasText $_ })
    if ($all.Count -eq 0) { return $null }
    return $all[0]
}

function Get-Assessment($Adapter) {
    if ($Adapter.Status -ne 'Up') {
        return 'SEM LINK — confira cabo, encaixe e equipamento na outra ponta. Não é possível determinar a causa apenas por esse estado.'
    }
    $v4 = @($Adapter.IPv4 | Where-Object { Test-HasText $_ })
    if ($v4.Count -eq 0) {
        return 'LINK ATIVO, SEM IPv4 — verifique DHCP ou configuração manual. Comunicação IPv4 ainda não testada.'
    }
    if (@($Adapter.IPv4States) -contains 'Duplicate') {
        return 'LINK ATIVO, IPv4 DUPLICADO — o Windows detectou outro equipamento usando o mesmo endereço nesta rede. Verifique a configuração manual ou o servidor DHCP.'
    }
    if (@($v4 | Where-Object { $_.StartsWith('169.254.') }).Count -eq $v4.Count) {
        return 'LINK ATIVO, IPv4 AUTOMÁTICO LOCAL — pode haver ausência de resposta DHCP. Esse endereço também pode permitir comunicação local.'
    }
    if ($Adapter.Speed -gt 0 -and $Adapter.Speed -lt 1e9) {
        return 'LINK ATIVO A ' + (Format-Speed $Adapter.Speed) + ' — capacidade observada nesta conexão; pode refletir a outra ponta, configuração ou cabeamento. Não comprova defeito.'
    }
    return 'LINK ATIVO — velocidade negociada e configuração disponíveis. Isso não certifica o cabeamento nem comprova comunicação.'
}

# ---------------------------------------------------------------------------------------------
# Inventário (Windows)
# ---------------------------------------------------------------------------------------------

function Invoke-Safe([scriptblock]$Block, $Notes, [string]$What) {
    try { return (& $Block) }
    catch {
        if ($null -ne $Notes) { $Notes.Add("${What}: indisponível ($($_.Exception.Message))") }
        return $null
    }
}

function Test-IsEthernetMedium($NetAdapter) {
    $medium = 0
    try { $medium = [int]$NetAdapter.NdisPhysicalMedium } catch { $medium = 0 }
    # 14 = NdisPhysicalMedium802_3 (Ethernet cabeada, inclusive adaptadores USB e docks).
    # 0 = não especificado; aceito apenas quando o tipo de mídia é 802.3.
    return ($medium -eq 14 -or ($medium -eq 0 -and "$($NetAdapter.MediaType)" -eq '802.3'))
}

function Test-IsWirelessMedium($NetAdapter) {
    $medium = 0
    try { $medium = [int]$NetAdapter.NdisPhysicalMedium } catch { $medium = 0 }
    return ($medium -eq 1 -or $medium -eq 9)
}

function Get-DefaultRouteSummary {
    $rows = @()
    foreach ($family in @(@{ Prefix = '0.0.0.0/0'; Name = 'IPv4' }, @{ Prefix = '::/0'; Name = 'IPv6' })) {
        foreach ($route in @(Get-NetRoute -DestinationPrefix $family.Prefix -PolicyStore ActiveStore -ErrorAction SilentlyContinue)) {
            $ipif = Get-NetIPInterface -InterfaceIndex $route.ifIndex -AddressFamily $family.Name -PolicyStore ActiveStore -ErrorAction SilentlyContinue
            if ($ipif -and "$($ipif.ConnectionState)" -ne 'Connected') { continue }
            $interfaceMetric = 0
            if ($ipif) { $interfaceMetric = [int]$ipif.InterfaceMetric }
            $rows += [pscustomobject]@{
                Family  = $family.Name
                Alias   = $route.InterfaceAlias
                Index   = [int]$route.ifIndex
                NextHop = $route.NextHop
                Metric  = [int]$route.RouteMetric + $interfaceMetric
            }
        }
    }
    return @($rows | Sort-Object Family, Metric)
}

function Get-LinkEvents([string]$Provider, [int]$Days = 7) {
    $result = [pscustomobject]@{ Lines = @(); Count = 0; Summary = ''; Note = '' }
    if (-not (Test-HasText $Provider)) { $result.Note = 'serviço do driver não identificado'; return $result }
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = $Provider; StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents 200 -ErrorAction Stop)
    } catch {
        if ("$($_.FullyQualifiedErrorId)" -like 'NoMatchingEventsFound*') {
            $result.Note = "nenhum evento do driver ($Provider) nos últimos $Days dias"
        } else {
            $result.Note = "log indisponível para $Provider ($($_.Exception.Message))"
        }
        return $result
    }
    $result.Count = $events.Count
    $result.Summary = (@($events | Group-Object Id | Sort-Object Count -Descending | ForEach-Object { "ID $($_.Name): $($_.Count)" }) -join ' | ')
    $result.Lines = @($events | Select-Object -First 25 | ForEach-Object {
            $message = "$($_.Message)"
            if (-not (Test-HasText $message)) { $message = '(texto do fabricante indisponível)' }
            $message = ($message -split "`r?`n")[0].Trim()
            if ($message.Length -gt 150) { $message = $message.Substring(0, 147) + '...' }
            '{0:yyyy-MM-dd HH:mm:ss}  ID {1,-5} {2}' -f $_.TimeCreated, $_.Id, $message
        })
    return $result
}

function Get-AdapterDetail($Nic, $Configs, $WmiNics, $GlobalNotes) {
    $index = [int]$Nic.ifIndex
    $notes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($n in $GlobalNotes) { $notes.Add($n) }

    $ips = @(Get-NetIPAddress -InterfaceIndex $index -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
    $v4 = @($ips | Where-Object { "$($_.AddressFamily)" -eq 'IPv4' } | Sort-Object { if ("$($_.IPAddress)".StartsWith('169.254.')) { 1 } else { 0 } })
    $v6 = @($ips | Where-Object { "$($_.AddressFamily)" -eq 'IPv6' })

    $gw4 = @(Get-NetRoute -InterfaceIndex $index -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | ForEach-Object { $_.NextHop } | Where-Object { (Test-HasText $_) -and $_ -ne '0.0.0.0' })
    $gw6 = @(Get-NetRoute -InterfaceIndex $index -DestinationPrefix '::/0' -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | ForEach-Object { $_.NextHop } | Where-Object { (Test-HasText $_) -and $_ -ne '::' })

    $dnsEntries = @(Get-DnsClientServerAddress -InterfaceIndex $index -ErrorAction SilentlyContinue)
    $dns4 = @($dnsEntries | Where-Object { "$($_.AddressFamily)" -in @('2', 'IPv4') } | ForEach-Object { $_.ServerAddresses } | Where-Object { Test-HasText $_ })
    $dns6 = @($dnsEntries | Where-Object { "$($_.AddressFamily)" -in @('23', 'IPv6') } | ForEach-Object { $_.ServerAddresses } |
            Where-Object { (Test-HasText $_) -and -not "$_".StartsWith('fec0:0:0:ffff::', [StringComparison]::OrdinalIgnoreCase) })
    $client = Get-DnsClient -InterfaceIndex $index -ErrorAction SilentlyContinue | Select-Object -First 1

    $ipif4 = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue | Select-Object -First 1
    $netProfile = Get-NetConnectionProfile -InterfaceIndex $index -ErrorAction SilentlyContinue | Select-Object -First 1
    $stats = Get-NetAdapterStatistics -Name $Nic.Name -ErrorAction SilentlyContinue | Select-Object -First 1
    $speedDuplex = Get-NetAdapterAdvancedProperty -Name $Nic.Name -RegistryKeyword '*SpeedDuplex' -ErrorAction SilentlyContinue | Select-Object -First 1
    $config = @($Configs | Where-Object { [int]$_.InterfaceIndex -eq $index }) | Select-Object -First 1
    $wmiNic = @($WmiNics | Where-Object { [int]$_.InterfaceIndex -eq $index }) | Select-Object -First 1

    $gatewayMac = $null; $gatewayMacState = $null
    if ($gw4.Count -gt 0) {
        $neighbor = Get-NetNeighbor -InterfaceIndex $index -IPAddress $gw4[0] -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($neighbor) { $gatewayMac = "$($neighbor.LinkLayerAddress)"; $gatewayMacState = "$($neighbor.State)" }
    }
    $neighborCount = @(Get-NetNeighbor -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { "$($_.State)" -in @('Reachable', 'Stale', 'Delay', 'Probe') }).Count

    $speedDuplexText = $null
    if ($speedDuplex) {
        $raw = "$(@($speedDuplex.RegistryValue)[0])"
        if ($raw -eq '0') { $speedDuplexText = "$($speedDuplex.DisplayValue) (negociação automática)" }
        else { $speedDuplexText = "$($speedDuplex.DisplayValue) (valor fixado no driver; a negociação automática pode estar desativada)" }
    }

    $dhcpText = 'não disponível'
    if ($ipif4) { $dhcpText = if ("$($ipif4.Dhcp)" -eq 'Enabled') { 'habilitado' } else { 'desabilitado / manual' } }

    $isUp = ("$($Nic.Status)" -eq 'Up')
    $duplexText = 'não aplicável (sem link)'
    if ($isUp) {
        $duplexText = 'não informado pelo driver'
        if ($null -ne $Nic.FullDuplex) { $duplexText = if ($Nic.FullDuplex) { 'full-duplex (informado pelo driver)' } else { 'half-duplex (informado pelo driver)' } }
    }

    return [pscustomobject]@{
        Id             = "$($Nic.InterfaceGuid)"
        Name           = $Nic.Name
        Description    = $Nic.InterfaceDescription
        Index          = $index
        Status         = "$($Nic.Status)"
        MediaState     = "$($Nic.MediaConnectionState)"
        Speed          = if ($isUp) { [double]$Nic.Speed } else { 0 }
        RxSpeed        = if ($isUp) { [double]$Nic.ReceiveLinkSpeed } else { 0 }
        TxSpeed        = if ($isUp) { [double]$Nic.TransmitLinkSpeed } else { 0 }
        Duplex         = $duplexText
        SpeedDuplexCfg = $speedDuplexText
        Mac            = "$($Nic.MacAddress)"
        Driver         = "$($Nic.DriverVersion)"
        DriverDate     = "$($Nic.DriverDate)"
        DriverProvider = "$($Nic.DriverProvider)"
        ServiceName    = if ($wmiNic) { "$($wmiNic.ServiceName)" } else { $null }
        IPv4           = @($v4 | ForEach-Object { "$($_.IPAddress)" })
        IPv4Prefix     = @($v4 | ForEach-Object { [int]$_.PrefixLength })
        IPv4States     = @($v4 | ForEach-Object { "$($_.AddressState)" })
        IPv6           = @($v6 | ForEach-Object { "$($_.IPAddress) [$($_.AddressState)]" })
        IPv6Global     = @($v6 | Where-Object { "$($_.AddressState)" -eq 'Preferred' -and -not "$($_.IPAddress)".StartsWith('fe80', [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { "$($_.IPAddress)" })
        Gateway4       = $gw4
        Gateway6       = $gw6
        GatewayMac     = $gatewayMac
        GatewayMacState = $gatewayMacState
        Neighbors      = $neighborCount
        Dns4           = $dns4
        Dns6           = $dns6
        DnsSuffix      = if ($client) { "$($client.ConnectionSpecificSuffix)" } else { $null }
        Dhcp           = $dhcpText
        DhcpServer     = if ($config) { "$($config.DHCPServer)" } else { $null }
        LeaseStart     = if ($config -and $config.DHCPLeaseObtained) { '{0:yyyy-MM-dd HH:mm:ss}' -f $config.DHCPLeaseObtained } else { $null }
        LeaseEnd       = if ($config -and $config.DHCPLeaseExpires) { '{0:yyyy-MM-dd HH:mm:ss}' -f $config.DHCPLeaseExpires } else { $null }
        Mtu4           = if ($ipif4) { [int]$ipif4.NlMtu } else { 0 }
        Metric4        = if ($ipif4) { [int]$ipif4.InterfaceMetric } else { $null }
        ProfileName    = if ($netProfile) { "$($netProfile.Name)" } else { $null }
        ProfileCategory = if ($netProfile) { "$($netProfile.NetworkCategory)" } else { $null }
        Connectivity4  = if ($netProfile) { "$($netProfile.IPv4Connectivity)" } else { $null }
        Connectivity6  = if ($netProfile) { "$($netProfile.IPv6Connectivity)" } else { $null }
        RxBytes        = if ($stats) { $stats.ReceivedBytes } else { $null }
        TxBytes        = if ($stats) { $stats.SentBytes } else { $null }
        RxErrors       = if ($stats) { $stats.ReceivedPacketErrors } else { $null }
        TxErrors       = if ($stats) { $stats.OutboundPacketErrors } else { $null }
        RxDiscarded    = if ($stats) { $stats.ReceivedDiscardedPackets } else { $null }
        TxDiscarded    = if ($stats) { $stats.OutboundDiscardedPackets } else { $null }
        Events         = $null
        Notes          = $notes
    }
}

function Get-EthernetInventory {
    $globalNotes = New-Object 'System.Collections.Generic.List[string]'
    $physical = @(Get-NetAdapter -Physical -ErrorAction Stop)
    $model = Invoke-Safe { (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Model } $globalNotes 'Modelo do computador (WMI)'
    $configs = @(Invoke-Safe { Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop } $globalNotes 'Dados DHCP (WMI)' | Where-Object { $null -ne $_ })
    $wmiNics = @(Invoke-Safe { Get-CimInstance -ClassName Win32_NetworkAdapter -Filter 'PhysicalAdapter=True' -ErrorAction Stop } $globalNotes 'Serviço do driver (WMI)' | Where-Object { $null -ne $_ })

    $adapters = @()
    foreach ($nic in $physical) {
        if (-not (Test-IsEthernetMedium $nic)) { continue }
        $detail = Get-AdapterDetail $nic $configs $wmiNics $globalNotes
        $detail.Events = Get-LinkEvents $detail.ServiceName
        $adapters += $detail
    }
    return [pscustomobject]@{
        Model    = $model
        Adapters = $adapters
        Wireless = @($physical | Where-Object { Test-IsWirelessMedium $_ } | ForEach-Object { "$($_.Name) — $($_.InterfaceDescription): $($_.Status)" })
        Routes   = Get-DefaultRouteSummary
    }
}

# ---------------------------------------------------------------------------------------------
# Relatório
# ---------------------------------------------------------------------------------------------

function Format-Report($Adapter, $Inventory) {
    $a = $Adapter
    $sb = New-Object System.Text.StringBuilder
    $add = { param($text) [void]$sb.AppendLine($text) }

    & $add ("DIAGNÓSTICO RJ45 $($script:AppVersion) (PowerShell) | " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    & $add ("Computador: " + (Format-Value $Inventory.Model))
    & $add ("Adaptador: " + (Format-Value $a.Description))
    & $add ("Interface: $($a.Name) (índice $($a.Index))")
    & $add ("Driver: " + (Format-Value $a.Driver) + " | data: " + (Format-Value $a.DriverDate) + " | fornecedor: " + (Format-Value $a.DriverProvider) + " | serviço: " + (Format-Value $a.ServiceName))
    & $add ("Estado: $($a.Status) | mídia: " + (Format-Value $a.MediaState))
    $speedText = if ($a.Status -eq 'Up') { Format-Speed $a.Speed } else { 'sem link' }
    if ($a.Status -eq 'Up' -and $a.RxSpeed -gt 0 -and $a.TxSpeed -gt 0 -and $a.RxSpeed -ne $a.TxSpeed) {
        $speedText += " (recepção " + (Format-Speed $a.RxSpeed) + " / transmissão " + (Format-Speed $a.TxSpeed) + ")"
    }
    & $add ("Velocidade negociada: $speedText")
    & $add ("Duplex: $($a.Duplex)")
    & $add ("Velocidade/duplex configurado no driver: " + (Format-Value $a.SpeedDuplexCfg))
    & $add ("MAC local: " + (Format-Value $a.Mac))
    & $add ("Perfil de rede: " + (Format-Value $a.ProfileName) + " | categoria: " + (Format-Value $a.ProfileCategory) + " | conectividade Windows IPv4: " + (Format-Value $a.Connectivity4) + " / IPv6: " + (Format-Value $a.Connectivity6))

    & $add ''
    & $add 'ENDEREÇAMENTO'
    $v4Lines = @()
    for ($i = 0; $i -lt @($a.IPv4).Count; $i++) {
        $v4Lines += "$(@($a.IPv4)[$i])/$(@($a.IPv4Prefix)[$i]) (máscara $(ConvertTo-IPv4Mask @($a.IPv4Prefix)[$i]); estado $(@($a.IPv4States)[$i]))"
    }
    & $add ("IPv4: " + (Format-Value $v4Lines))
    & $add ("IPv6: " + (Format-Value $a.IPv6))
    & $add ("Gateway IPv4: " + (Format-Value $a.Gateway4))
    & $add ("Gateway IPv6: " + (Format-Value $a.Gateway6))
    if (Test-HasText $a.GatewayMac) {
        & $add ("MAC do gateway IPv4: $($a.GatewayMac) (vizinho $($a.GatewayMacState)) — " + (Get-MacInfo $a.GatewayMac))
        & $add '  Identifica o gateway (roteador/firewall), não necessariamente o switch onde o cabo termina.'
    } else {
        & $add 'MAC do gateway IPv4: não disponível (gateway ainda não contatado ou inexistente).'
    }
    & $add ("Vizinhos IPv4 vistos recentemente nesta Ethernet: $($a.Neighbors)")
    & $add ("DNS IPv4: " + (Format-Value $a.Dns4) + " | DNS IPv6: " + (Format-Value $a.Dns6))
    & $add ("Sufixo DNS: " + (Format-Value $a.DnsSuffix))
    & $add ("DHCP: $($a.Dhcp) | servidor: " + (Format-Value $a.DhcpServer) + " | concessão: " + (Format-Value $a.LeaseStart) + " até " + (Format-Value $a.LeaseEnd))
    $mtuText = if ($a.Mtu4 -gt 0) { "$($a.Mtu4) bytes" } else { 'não disponível' }
    & $add ("MTU IPv4 configurada na interface: $mtuText | métrica da interface: " + (Format-Value $a.Metric4))

    & $add ''
    & $add (Get-Assessment $a)

    & $add ''
    & $add 'ROTAS PADRÃO ATIVAS NO COMPUTADOR (métrica efetiva; a menor é a preferida pelo Windows)'
    $routes = @($Inventory.Routes)
    if ($routes.Count -eq 0) { & $add '  nenhuma rota padrão ativa' }
    foreach ($family in @('IPv4', 'IPv6')) {
        $familyRoutes = @($routes | Where-Object { $_.Family -eq $family })
        for ($i = 0; $i -lt $familyRoutes.Count; $i++) {
            $r = $familyRoutes[$i]
            $mark = if ($i -eq 0) { '  <- preferida' } else { '' }
            $self = if ($r.Index -eq $a.Index) { ' [esta Ethernet]' } else { '' }
            & $add ("  $family  $($r.Alias) (índice $($r.Index))$self via $($r.NextHop), métrica $($r.Metric)$mark")
        }
        if ($familyRoutes.Count -gt 0 -and $familyRoutes[0].Index -ne $a.Index) {
            & $add "  Atenção: o tráfego $family comum deste computador sai por outra interface. Os testes deste aplicativo fixam origem e rota na Ethernet selecionada e recusam o que sairia por outra interface."
        }
    }
    & $add ("Interfaces sem fio: " + (Format-Value $Inventory.Wireless))

    & $add ''
    & $add 'CONTADORES ACUMULADOS DO ADAPTADOR (desde a inicialização do driver; não são medições do cabo)'
    & $add ("Recebidos: " + (Format-Value $a.RxBytes) + " bytes | enviados: " + (Format-Value $a.TxBytes) + " bytes")
    & $add ("Erros RX/TX: " + (Format-Value $a.RxErrors) + " / " + (Format-Value $a.TxErrors) + " | descartes RX/TX: " + (Format-Value $a.RxDiscarded) + " / " + (Format-Value $a.TxDiscarded))

    & $add ''
    & $add 'EVENTOS DO DRIVER NO LOG DO SISTEMA (últimos 7 dias)'
    if ($a.Events -and $a.Events.Count -gt 0) {
        & $add ("Total: $($a.Events.Count) | por ID: $($a.Events.Summary)")
        foreach ($line in $a.Events.Lines) { & $add "  $line" }
        if ($a.Events.Count -gt 25) { & $add '  (exibindo os 25 mais recentes)' }
        & $add '  Quedas e retornos de link aparecem aqui conforme o fabricante do driver. Se houver mais de um adaptador com o mesmo driver, confira a interface citada na mensagem.'
    } elseif ($a.Events) {
        & $add ("  " + $a.Events.Note)
    }

    if ($a.Notes -and $a.Notes.Count -gt 0) {
        & $add ''
        & $add 'OBSERVAÇÕES DE CONSULTA'
        foreach ($n in $a.Notes) { & $add "  $n" }
    }

    & $add ''
    & $add 'RECURSOS NÃO DISPONÍVEIS NESTA VERSÃO'
    & $add 'Mapa dos 8 fios, comprimento, distância até falhas, PoE, interferência e certificação Cat5e/Cat6/Cat6A.'
    & $add 'Identificação do switch, porta e VLAN (LLDP/CDP) não implementada.'
    & $add 'Velocidade negociada não é velocidade real de transferência.'
    return $sb.ToString()
}

# ---------------------------------------------------------------------------------------------
# Testes ativos (Windows). $Write recebe cada linha de resultado.
# ---------------------------------------------------------------------------------------------

function Assert-RouteOnAdapter([string]$Target, [string]$Source, [int]$Index) {
    $parameters = @{ RemoteIPAddress = $Target; ErrorAction = 'Stop' }
    if (Test-HasText $Source) { $parameters.LocalIPAddress = $Source }
    try { $found = @(Find-NetRoute @parameters) }
    catch { throw "Sem rota para $Target pela configuração atual: $($_.Exception.Message)" }
    $route = $found | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' } | Select-Object -First 1
    $address = $found | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetIPAddress' } | Select-Object -First 1
    if (-not $route) { throw "O Windows não retornou rota para $Target." }
    if ([int]$route.InterfaceIndex -ne $Index) {
        throw "A rota para $Target sairia por outra interface ($($route.InterfaceAlias), índice $($route.InterfaceIndex)), não pela Ethernet selecionada."
    }
    if ((Test-HasText $Source) -and $address -and -not (Test-SameIPAddress "$($address.IPAddress)" $Source)) {
        throw "A origem escolhida pelo Windows ($($address.IPAddress)) não corresponde à Ethernet selecionada ($Source)."
    }
}

function Invoke-Ping {
    param([string]$Target, [string]$Source, [switch]$IPv6, [int]$Size = 32, [switch]$DontFragment, [int]$Ttl = 0, [int]$TimeoutMs = 1000)
    $arguments = New-Object 'System.Collections.Generic.List[string]'
    if ($IPv6) { $arguments.Add('-6') } else { $arguments.Add('-4') }
    foreach ($x in @('-n', '1', '-w', "$TimeoutMs", '-l', "$Size")) { $arguments.Add($x) }
    if ($DontFragment -and -not $IPv6) { $arguments.Add('-f') }
    if ($Ttl -gt 0) { $arguments.Add('-i'); $arguments.Add("$Ttl") }
    if (Test-HasText $Source) { $arguments.Add('-S'); $arguments.Add($Source) }
    $arguments.Add($Target)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& $script:PingExe $arguments.ToArray() 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $previous }
    return (ConvertFrom-PingOutput $output $Target $Source)
}

function Get-IPv4TestContext($Adapter, [string]$Target) {
    if ($Adapter.Status -ne 'Up') { throw 'Sem link na Ethernet selecionada. Conecte o cabo e clique em Atualizar.' }
    $source = Get-PrimaryIPv4 $Adapter
    if (-not $source) { throw 'A Ethernet selecionada não tem endereço IPv4.' }
    if (-not (Test-HasText $Target)) { $Target = @($Adapter.Gateway4)[0] }
    if (-not (Test-HasText $Target)) { throw 'A Ethernet não tem gateway IPv4. Informe um destino IPv4 no campo Destino.' }
    $Target = $Target.Trim()
    if (-not (Test-IPv4Text $Target)) { throw "Destino IPv4 inválido: $Target" }
    return [pscustomobject]@{ Source = $source; Target = $Target }
}

function Invoke-IPv4Test($Adapter, [string]$Target, [scriptblock]$Write, [int]$Count = 10) {
    $ctx = Get-IPv4TestContext $Adapter $Target
    & $Write ''
    & $Write "TESTE IPv4 (ICMP) | destino $($ctx.Target) | origem $($ctx.Source) | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $latencies = New-Object 'System.Collections.Generic.List[int]'
    for ($n = 1; $n -le $Count; $n++) {
        Assert-RouteOnAdapter $ctx.Target $ctx.Source $Adapter.Index
        $r = Invoke-Ping -Target $ctx.Target -Source $ctx.Source
        if ($r.Kind -eq 'reply') {
            $latencies.Add([int]$r.Latency)
            & $Write "Pacote $n/${Count}: resposta em $(Format-Latency $r)"
        } else {
            & $Write "Pacote $n/${Count}: sem resposta bem-sucedida ($($r.Message))"
        }
        Start-Sleep -Milliseconds 200
    }
    $ok = $latencies.Count
    & $Write ("Respostas: $ok/$Count | ausência de resposta: {0:0}%." -f (($Count - $ok) * 100.0 / $Count))
    if ($ok -gt 0) {
        $stats = $latencies | Measure-Object -Minimum -Maximum -Average
        & $Write ("Latência mín/média/máx: {0} / {1:0.0} / {2} ms (valores abaixo de 1 ms contados como 0)." -f $stats.Minimum, $stats.Average, $stats.Maximum)
    }
    & $Write 'Ausência de resposta pode ser bloqueio ICMP, destino indisponível ou falha de rede; não identifica sozinha defeito no cabo.'
}

function Invoke-DnsTest($Adapter, [string]$Name, [scriptblock]$Write) {
    if (-not (Test-HasText $Name)) { $Name = 'www.microsoft.com' }
    $Name = $Name.Trim()
    & $Write ''
    & $Write "TESTE DNS | nome $Name | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    if ($Adapter.Status -ne 'Up') { throw 'Sem link na Ethernet selecionada.' }
    $servers = @(@($Adapter.Dns4) + @($Adapter.Dns6) | Where-Object { Test-HasText $_ })
    if ($servers.Count -eq 0) { & $Write 'A Ethernet selecionada não tem servidores DNS configurados; teste não executado.'; return }
    foreach ($server in $servers) {
        try { Assert-RouteOnAdapter $server $null $Adapter.Index }
        catch { & $Write "DNS ${server}: não testado — $($_.Exception.Message)"; continue }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $answers = @(Resolve-DnsName -Name $Name -Server $server -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop)
            $watch.Stop()
            $ips = @($answers | Where-Object { "$($_.Type)" -in @('A', 'AAAA') } | ForEach-Object { "$($_.IPAddress)" })
            $result = if ($ips.Count -gt 0) { $ips -join ', ' } else { 'resposta sem endereços A/AAAA' }
            & $Write "DNS ${server}: respondeu em $($watch.ElapsedMilliseconds) ms — $Name -> $result"
        } catch {
            $watch.Stop()
            & $Write "DNS ${server}: falha após $($watch.ElapsedMilliseconds) ms — $($_.Exception.Message)"
        }
    }
    & $Write 'A consulta DNS não permite fixar o endereço de origem; por isso cada servidor só é testado quando o Windows confirma que a rota até ele é a Ethernet selecionada.'
}

function Invoke-IPv6Test($Adapter, [string]$Target, [scriptblock]$Write, [int]$Count = 4) {
    & $Write ''
    if ($Adapter.Status -ne 'Up') { throw 'Sem link na Ethernet selecionada.' }
    if ((Test-HasText $Target) -and -not (Test-IPv6Text $Target)) { $Target = $null }
    if (-not (Test-HasText $Target)) { $Target = @($Adapter.Gateway6)[0] }
    if (-not (Test-HasText $Target)) {
        & $Write 'TESTE IPv6: a Ethernet selecionada não tem gateway IPv6 e nenhum destino IPv6 foi informado; teste não executado.'
        return
    }
    $bare = ($Target.Trim() -split '%')[0]
    $address = [System.Net.IPAddress]::Parse($bare)
    $source = $null
    if ($address.IsIPv6LinkLocal) {
        $destination = "$bare%$($Adapter.Index)"
        $scopeNote = "endereço de enlace local com escopo fixado na interface $($Adapter.Index)"
    } else {
        $destination = $bare
        $source = @($Adapter.IPv6Global)[0]
        if (-not $source) { throw 'A Ethernet não tem IPv6 global para testar um destino fora do enlace local.' }
        Assert-RouteOnAdapter $destination $source $Adapter.Index
        $scopeNote = "origem $source"
    }
    & $Write "TESTE IPv6 (ICMPv6) | destino $destination | $scopeNote | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $ok = 0
    for ($n = 1; $n -le $Count; $n++) {
        if ($source) { Assert-RouteOnAdapter $destination $source $Adapter.Index }
        $r = Invoke-Ping -Target $destination -Source $source -IPv6
        if ($r.Kind -eq 'reply') { $ok++; & $Write "Pacote $n/${Count}: resposta em $(Format-Latency $r)" }
        else { & $Write "Pacote $n/${Count}: sem resposta bem-sucedida ($($r.Message))" }
        Start-Sleep -Milliseconds 200
    }
    & $Write "Respostas IPv6: $ok/$Count."
}

function Invoke-MtuTest($Adapter, [string]$Target, [scriptblock]$Write) {
    $ctx = Get-IPv4TestContext $Adapter $Target
    Assert-RouteOnAdapter $ctx.Target $ctx.Source $Adapter.Index
    & $Write ''
    & $Write "TESTE DE MTU (ICMP sem fragmentação) | destino $($ctx.Target) | origem $($ctx.Source)"
    $probe = {
        param([int]$Size)
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            $r = Invoke-Ping -Target $ctx.Target -Source $ctx.Source -Size $Size -DontFragment
            if ($r.Kind -eq 'reply') { return $true }
        }
        return $false
    }
    if (-not (& $probe 32)) { & $Write 'O destino não respondeu a pacotes pequenos; MTU não determinada.'; return }
    $configured = [int]$Adapter.Mtu4
    $max = if ($configured -ge 576) { $configured - 28 } else { 1472 }
    if (& $probe $max) {
        $best = $max
    } else {
        $low = 32; $high = $max
        while (($high - $low) -gt 1) {
            $middle = [int][math]::Floor(($low + $high) / 2)
            if (& $probe $middle) { $low = $middle } else { $high = $middle }
        }
        $best = $low
    }
    & $Write ("Maior carga ICMP aceita sem fragmentação: $best bytes -> MTU do caminho até o destino ≈ $($best + 28) bytes (MTU da interface: " + $(if ($configured -gt 0) { "$configured" } else { 'não disponível' }) + ').')
    if ($best -lt $max) { & $Write 'Valor menor que a MTU da interface: pacotes grandes podem estar sendo descartados no caminho, ou o destino limita respostas ICMP.' }
}

function Invoke-RouteTrace($Adapter, [string]$Target, [scriptblock]$Write, [int]$MaxHops = 15) {
    if (-not (Test-HasText $Target)) { $Target = '8.8.8.8' }
    $ctx = Get-IPv4TestContext $Adapter $Target
    Assert-RouteOnAdapter $ctx.Target $ctx.Source $Adapter.Index
    & $Write ''
    & $Write "RASTREAMENTO DE ROTA IPv4 | destino $($ctx.Target) | origem $($ctx.Source) | até $MaxHops saltos"
    $misses = 0
    for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
        $r = Invoke-Ping -Target $ctx.Target -Source $ctx.Source -Ttl $ttl
        switch ($r.Kind) {
            'reply' { & $Write ("{0,2}  {1}  destino alcançado ({2})" -f $ttl, $ctx.Target, (Format-Latency $r)); return }
            'hop' { & $Write ("{0,2}  {1}  {2}" -f $ttl, $r.Responder, $r.Message); $misses = 0 }
            'local' { & $Write ("{0,2}  (este computador)  {1}" -f $ttl, $r.Message); return }
            default {
                & $Write ("{0,2}  *  sem resposta" -f $ttl); $misses++
                if ($misses -ge 4) { & $Write 'Quatro saltos seguidos sem resposta; rastreamento encerrado (equipamentos podem não responder ICMP).'; return }
            }
        }
    }
    & $Write "Limite de $MaxHops saltos atingido."
}

# ---------------------------------------------------------------------------------------------
# Verificações
# ---------------------------------------------------------------------------------------------

function Invoke-UnitChecks {
    $failures = New-Object 'System.Collections.Generic.List[string]'
    $check = { param([bool]$Condition, [string]$Name) if (-not $Condition) { $failures.Add($Name) } }

    & $check ((Format-Speed 100e6) -eq '100 Mb/s') 'Velocidade 100 Mb/s'
    & $check ((Format-Speed 1e9) -eq '1 Gb/s') 'Velocidade 1 Gb/s'
    & $check ((Format-Speed 0) -eq 'indisponível') 'Velocidade indisponível'
    & $check ((ConvertTo-IPv4Mask 24) -eq '255.255.255.0') 'Máscara /24'
    & $check ((ConvertTo-IPv4Mask 22) -eq '255.255.252.0') 'Máscara /22'
    & $check ((ConvertTo-IPv4Mask 32) -eq '255.255.255.255') 'Máscara /32'
    & $check ((ConvertTo-IPv4Mask 0) -eq '0.0.0.0') 'Máscara /0'

    & $check ((Get-Assessment ([pscustomobject]@{ Status = 'Disconnected'; IPv4 = @(); IPv4States = @(); Speed = 0 })).StartsWith('SEM LINK')) 'Estado desconectado'
    & $check ((Get-Assessment ([pscustomobject]@{ Status = 'Up'; IPv4 = @(); IPv4States = @(); Speed = 1e9 })).StartsWith('LINK ATIVO, SEM')) 'Sem IPv4'
    & $check ((Get-Assessment ([pscustomobject]@{ Status = 'Up'; IPv4 = @('169.254.1.1'); IPv4States = @('Preferred'); Speed = 1e9 })).Contains('AUTOMÁTICO')) 'IPv4 automático'
    & $check ((Get-Assessment ([pscustomobject]@{ Status = 'Up'; IPv4 = @('10.0.0.2'); IPv4States = @('Duplicate'); Speed = 1e9 })).Contains('DUPLICADO')) 'IPv4 duplicado'
    & $check ((Get-Assessment ([pscustomobject]@{ Status = 'Up'; IPv4 = @('10.0.0.2'); IPv4States = @('Preferred'); Speed = 100e6 })).StartsWith('LINK ATIVO A 100')) 'Link 100 Mb/s'
    & $check ((Get-Assessment ([pscustomobject]@{ Status = 'Up'; IPv4 = @('10.0.0.2'); IPv4States = @('Preferred'); Speed = 1e9 })).StartsWith('LINK ATIVO —')) 'Link gigabit'

    $r = ConvertFrom-PingOutput @('', 'Disparando 10.0.0.1 com 32 bytes de dados:', 'Resposta de 10.0.0.1: bytes=32 tempo=2ms TTL=64', '', 'Estatísticas do Ping para 10.0.0.1:') '10.0.0.1' '10.0.0.5'
    & $check ($r.Kind -eq 'reply' -and $r.Latency -eq 2) 'Ping pt-BR resposta'
    $r = ConvertFrom-PingOutput @('Disparando 10.0.0.1 de 10.0.0.5 com 32 bytes de dados:', 'Resposta de 10.0.0.1: bytes=32 tempo<1ms TTL=64') '10.0.0.1' '10.0.0.5'
    & $check ($r.Kind -eq 'reply' -and $r.LessThanOne) 'Ping pt-BR <1ms'
    $r = ConvertFrom-PingOutput @('Pinging 10.0.0.1 from 10.0.0.5 with 32 bytes of data:', 'Reply from 10.0.0.1: bytes=32 time=3ms TTL=255') '10.0.0.1' '10.0.0.5'
    & $check ($r.Kind -eq 'reply' -and $r.Latency -eq 3) 'Ping inglês resposta'
    $r = ConvertFrom-PingOutput @('Disparando 10.0.0.1 com 32 bytes de dados:', 'Esgotado o tempo limite do pedido.') '10.0.0.1' '10.0.0.5'
    & $check ($r.Kind -eq 'noreply') 'Ping tempo esgotado'
    $r = ConvertFrom-PingOutput @('Disparando 10.0.0.9 com 32 bytes de dados:', 'Resposta de 10.0.0.5: Host de destino inacessível.') '10.0.0.9' '10.0.0.5'
    & $check ($r.Kind -eq 'local' -and $r.Message -eq 'Host de destino inacessível.') 'Ping inacessível local'
    $r = ConvertFrom-PingOutput @('Disparando 8.8.8.8 com 32 bytes de dados:', 'Resposta de 192.168.1.1: TTL expirado em trânsito.') '8.8.8.8' '10.0.0.5'
    & $check ($r.Kind -eq 'hop' -and $r.Responder -eq '192.168.1.1' -and $r.Message -eq 'TTL expirado em trânsito.') 'Ping TTL expirado'
    $r = ConvertFrom-PingOutput @('Disparando 10.0.0.1 com 1472 bytes de dados:', 'O pacote precisa ser fragmentado, mas DF está definido.') '10.0.0.1' '10.0.0.5'
    & $check ($r.Kind -eq 'noreply') 'Ping fragmentação'
    $r = ConvertFrom-PingOutput @('Falha na solicitação de ping. Não foi possível encontrar o host x.') 'x' '10.0.0.5'
    & $check ($r.Kind -eq 'error') 'Ping erro de comando'
    $r = ConvertFrom-PingOutput @('Disparando fe80::1%12 com 32 bytes de dados:', 'Resposta de fe80::1%12: tempo<1ms') 'fe80::1%12' $null
    & $check ($r.Kind -eq 'reply') 'Ping IPv6 enlace local'
    $r = ConvertFrom-PingOutput @('Pinging 2001:db8::1 from 2001:db8::5 with 32 bytes of data:', 'Reply from 2001:db8::1: time=5ms') '2001:db8::1' '2001:db8::5'
    & $check ($r.Kind -eq 'reply' -and $r.Latency -eq 5) 'Ping IPv6 global'

    & $check ((Get-MacInfo '00-00-0C-07-AC-0A').Contains('HSRP')) 'MAC HSRP'
    & $check ((Get-MacInfo '00-00-5E-00-01-05').Contains('VRRP')) 'MAC VRRP'
    & $check ((Get-MacInfo '02-11-22-33-44-55').Contains('administrado localmente')) 'MAC local'
    & $check ((Get-MacInfo 'A4-BB-6D-11-22-33').Contains('A4-BB-6D')) 'MAC OUI'
    & $check ((Get-MacInfo '00-00-00-00-00-00') -eq 'não disponível') 'MAC vazio'
    & $check (Test-IPv4Text '10.1.2.3') 'IPv4 válido'
    & $check (-not (Test-IPv4Text 'destino-invalido')) 'IPv4 inválido'
    & $check (Test-IPv6Text 'fe80::1%7') 'IPv6 com escopo'
    return $failures
}

if ($UnitTest -or $SelfTest) {
    $failures = Invoke-UnitChecks
    if ($failures.Count -gt 0) {
        [Console]::Error.WriteLine('Falhas nas verificações: ' + ($failures -join '; '))
        exit 1
    }
    Write-Output 'Verificações de interpretação: OK'
    if ($UnitTest) { exit 0 }
    try {
        $loopback = Get-NetIPInterface -AddressFamily IPv4 -PolicyStore ActiveStore | Where-Object { "$($_.InterfaceAlias)" -like 'Loopback*' } | Select-Object -First 1
        Assert-RouteOnAdapter '127.0.0.1' '127.0.0.1' ([int]$loopback.ifIndex)
        $r = Invoke-Ping -Target '127.0.0.1' -Source '127.0.0.1'
        if ($r.Kind -ne 'reply') { throw "ICMP de loopback não respondeu: $($r.Message)" }
        Write-Output 'Rota e ICMP de loopback: OK'
        $inventory = Get-EthernetInventory
        Write-Output "Adaptadores Ethernet encontrados: $(@($inventory.Adapters).Count)"
        foreach ($adapter in $inventory.Adapters) { Write-Output ''; Write-Output (Format-Report $adapter $inventory) }
        exit 0
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}

# ---------------------------------------------------------------------------------------------
# Interface gráfica
# ---------------------------------------------------------------------------------------------

if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host "O PowerShell deste computador está em modo '$($ExecutionContext.SessionState.LanguageMode)'. A interface gráfica não pode ser carregada nesse modo; nenhuma configuração foi alterada."
    exit 3
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Write-Host "Diagnóstico RJ45 $($script:AppVersion) em execução. Mantenha esta janela aberta enquanto usa o aplicativo."

$script:Inventory = $null
$script:Adapters = @()
$script:Busy = $false
$script:Suppress = $false
$script:TestLogs = @{}
$script:LastId = $null
$script:LastState = $null
$script:Transitions = 0

$form = New-Object System.Windows.Forms.Form
$form.Text = "Diagnóstico RJ45 $($script:AppVersion) — Portátil (PowerShell)"
$form.Width = 1140; $form.Height = 820
$form.MinimumSize = New-Object System.Drawing.Size(900, 650)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'; $layout.Padding = New-Object System.Windows.Forms.Padding(20); $layout.ColumnCount = 1; $layout.RowCount = 7
foreach ($h in @(46, 28, 38, 86, 44)) { [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, $h))) }
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
$form.Controls.Add($layout)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'RJ45  /  Diagnóstico de ponto de rede'; $title.Dock = 'Fill'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(15, 45, 75)
$layout.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Componentes do próprio Windows • testes presos à Ethernet selecionada • sem instalação e sem logs automáticos'
$subtitle.Dock = 'Fill'
$layout.Controls.Add($subtitle)

$combo = New-Object System.Windows.Forms.ComboBox
$combo.Dock = 'Fill'; $combo.DropDownStyle = 'DropDownList'
$layout.Controls.Add($combo)

function New-ActionButton([string]$Text) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.AutoSize = $true; $b.Height = 32
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 6)
    return $b
}
$actions = New-Object System.Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Fill'; $actions.WrapContents = $true
$btnRefresh = New-ActionButton 'Atualizar'
$btnFull = New-ActionButton 'Teste completo'
$btnIPv4 = New-ActionButton 'IPv4 (10 pacotes)'
$btnDns = New-ActionButton 'DNS'
$btnIPv6 = New-ActionButton 'IPv6'
$btnMtu = New-ActionButton 'MTU'
$btnTrace = New-ActionButton 'Rastrear rota'
$btnCopy = New-ActionButton 'Copiar relatório'
$btnSave = New-ActionButton 'Salvar relatório'
$monitor = New-Object System.Windows.Forms.CheckBox
$monitor.Text = 'Acompanhar link (8 s)'; $monitor.AutoSize = $true; $monitor.Margin = New-Object System.Windows.Forms.Padding(8, 6, 0, 0)
$script:ActionControls = @($btnRefresh, $btnFull, $btnIPv4, $btnDns, $btnIPv6, $btnMtu, $btnTrace, $btnCopy, $btnSave, $combo)
foreach ($c in @($btnRefresh, $btnFull, $btnIPv4, $btnDns, $btnIPv6, $btnMtu, $btnTrace, $btnCopy, $btnSave, $monitor)) { $actions.Controls.Add($c) }
$layout.Controls.Add($actions)

function New-FieldLabel([string]$Text) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.AutoSize = $true; $l.Margin = New-Object System.Windows.Forms.Padding(0, 8, 6, 0)
    return $l
}
$fields = New-Object System.Windows.Forms.FlowLayoutPanel
$fields.Dock = 'Fill'
$txtTarget = New-Object System.Windows.Forms.TextBox; $txtTarget.Width = 200
$txtDns = New-Object System.Windows.Forms.TextBox; $txtDns.Width = 190; $txtDns.Text = 'www.microsoft.com'
$txtTrace = New-Object System.Windows.Forms.TextBox; $txtTrace.Width = 140; $txtTrace.Text = '8.8.8.8'
$fields.Controls.Add((New-FieldLabel 'Destino (em branco = gateway):'))
$fields.Controls.Add($txtTarget)
$fields.Controls.Add((New-FieldLabel '   Nome DNS:'))
$fields.Controls.Add($txtDns)
$fields.Controls.Add((New-FieldLabel '   Destino da rota:'))
$fields.Controls.Add($txtTrace)
$layout.Controls.Add($fields)

$reportBox = New-Object System.Windows.Forms.TextBox
$reportBox.Multiline = $true; $reportBox.ReadOnly = $true; $reportBox.ScrollBars = 'Vertical'; $reportBox.Dock = 'Fill'
$reportBox.Font = New-Object System.Drawing.Font('Consolas', 10); $reportBox.BackColor = [System.Drawing.Color]::White
$reportBox.Text = "Conecte o cabo ao notebook e ao ponto de rede.`r`nClique em Atualizar para ler a porta RJ45.`r`n`r`nA ferramenta verifica link e comunicação; não certifica o cabo."
$layout.Controls.Add($reportBox)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock = 'Fill'; $statusLabel.Text = 'Portátil: resultados em memória. Salve um relatório somente se desejar.'
$layout.Controls.Add($statusLabel)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 8000

function Get-SelectedAdapter {
    $i = $combo.SelectedIndex
    if ($i -lt 0 -or $i -ge @($script:Adapters).Count) { return $null }
    return @($script:Adapters)[$i]
}

function Get-TestLog([string]$Id) {
    if (-not $script:TestLogs.ContainsKey($Id)) { $script:TestLogs[$Id] = New-Object System.Text.StringBuilder }
    return $script:TestLogs[$Id]
}

function Show-SelectedReport {
    $a = Get-SelectedAdapter
    if (-not $a) { return }
    if ($script:LastId -eq $a.Id -and $null -ne $script:LastState -and $script:LastState -ne $a.Status) { $script:Transitions++ }
    if ($script:LastId -ne $a.Id) { $script:Transitions = 0 }
    $script:LastId = $a.Id; $script:LastState = $a.Status
    $text = (Format-Report $a $script:Inventory) + "`r`nMudanças de estado observadas pelo aplicativo: $($script:Transitions) (amostragem a cada atualização; eventos entre amostras podem não ser vistos).`r`n"
    $log = (Get-TestLog $a.Id).ToString()
    if ($log.Length -gt 0) { $text += "`r`n===== TESTES DESTA SESSÃO =====`r`n" + $log }
    $reportBox.Text = $text
}

function Add-ResultLine([string]$Line) {
    $a = Get-SelectedAdapter
    if ($a) { [void](Get-TestLog $a.Id).AppendLine($Line) }
    $reportBox.AppendText($Line + "`r`n")
    if (Test-HasText $Line) { $statusLabel.Text = $Line }
    [System.Windows.Forms.Application]::DoEvents()
}
$script:Writer = { param($line) Add-ResultLine $line }

function Set-Busy([bool]$Value, [string]$Text) {
    $script:Busy = $Value
    foreach ($c in $script:ActionControls) { $c.Enabled = -not $Value }
    $form.Cursor = if ($Value) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
    if ($Text) { $statusLabel.Text = $Text }
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-Inventory {
    $previous = Get-SelectedAdapter
    $script:Inventory = Get-EthernetInventory
    $script:Adapters = @($script:Inventory.Adapters)
    $script:Suppress = $true
    try {
        $combo.Items.Clear()
        foreach ($a in $script:Adapters) { [void]$combo.Items.Add("$($a.Name) — $($a.Description) [$($a.Status)]") }
        $pick = -1
        for ($i = 0; $i -lt $script:Adapters.Count; $i++) { if ($previous -and $script:Adapters[$i].Id -eq $previous.Id) { $pick = $i } }
        if ($pick -lt 0) { for ($i = 0; $i -lt $script:Adapters.Count; $i++) { if ($pick -lt 0 -and $script:Adapters[$i].Status -eq 'Up') { $pick = $i } } }
        if ($pick -lt 0 -and $script:Adapters.Count -gt 0) { $pick = 0 }
        if ($pick -ge 0) { $combo.SelectedIndex = $pick }
    } finally { $script:Suppress = $false }
    if ($script:Adapters.Count -eq 0) {
        $reportBox.Text = "Nenhum adaptador Ethernet físico foi encontrado.`r`nAdaptadores Wi-Fi, VPN e virtuais não são listados de propósito.`r`n`r`nInterfaces sem fio: " + (Format-Value $script:Inventory.Wireless)
    } else {
        Show-SelectedReport
    }
    $statusLabel.Text = 'Atualizado às ' + (Get-Date -Format 'HH:mm:ss') + '. Link ativo não equivale a cabo certificado.'
}

function Invoke-UiAction([string]$Text, [scriptblock]$Action) {
    if ($script:Busy) { return }
    Set-Busy $true $Text
    try { & $Action }
    catch {
        try { Add-ResultLine ("Interrompido: " + $_.Exception.Message) } catch { }
        $statusLabel.Text = 'Ação não concluída. Consulte o relatório.'
    }
    finally { Set-Busy $false $null }
}

function Invoke-AdapterTest([scriptblock]$Test) {
    $monitor.Checked = $false
    Invoke-UiAction 'Atualizando a Ethernet antes do teste...' {
        Update-Inventory
        $a = Get-SelectedAdapter
        if (-not $a) { throw 'Nenhuma Ethernet selecionada.' }
        & $Test $a
        $statusLabel.Text = 'Teste concluído às ' + (Get-Date -Format 'HH:mm:ss') + '.'
    }
}

$btnRefresh.Add_Click({ Invoke-UiAction 'Consultando a Ethernet...' { Update-Inventory } })
$btnIPv4.Add_Click({ Invoke-AdapterTest { param($a) Invoke-IPv4Test $a $txtTarget.Text $script:Writer } })
$btnDns.Add_Click({ Invoke-AdapterTest { param($a) Invoke-DnsTest $a $txtDns.Text $script:Writer } })
$btnIPv6.Add_Click({ Invoke-AdapterTest { param($a) Invoke-IPv6Test $a $txtTarget.Text $script:Writer } })
$btnMtu.Add_Click({ Invoke-AdapterTest { param($a) Invoke-MtuTest $a $txtTarget.Text $script:Writer } })
$btnTrace.Add_Click({ Invoke-AdapterTest { param($a) Invoke-RouteTrace $a $txtTrace.Text $script:Writer } })
$btnFull.Add_Click({
        Invoke-AdapterTest {
            param($a)
            $steps = @(
                @{ Name = 'IPv4'; Block = { Invoke-IPv4Test $a $txtTarget.Text $script:Writer } },
                @{ Name = 'DNS'; Block = { Invoke-DnsTest $a $txtDns.Text $script:Writer } },
                @{ Name = 'IPv6'; Block = { Invoke-IPv6Test $a $txtTarget.Text $script:Writer } },
                @{ Name = 'MTU'; Block = { Invoke-MtuTest $a $txtTarget.Text $script:Writer } },
                @{ Name = 'Rota'; Block = { Invoke-RouteTrace $a $txtTrace.Text $script:Writer } }
            )
            foreach ($step in $steps) {
                try { & $step.Block }
                catch { Add-ResultLine ("$($step.Name): interrompido — " + $_.Exception.Message) }
            }
        }
    })
$btnCopy.Add_Click({
        try { [System.Windows.Forms.Clipboard]::SetText($reportBox.Text); $statusLabel.Text = 'Relatório copiado para a área de transferência.' }
        catch { $statusLabel.Text = 'Não foi possível copiar: ' + $_.Exception.Message }
    })
$btnSave.Add_Click({
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = 'Relatório de texto (*.txt)|*.txt'
        $dialog.FileName = 'diagnostico-rj45-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'
        try {
            if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
                [System.IO.File]::WriteAllText($dialog.FileName, $reportBox.Text, (New-Object System.Text.UTF8Encoding($true)))
                $statusLabel.Text = 'Relatório salvo em ' + $dialog.FileName
            }
        } catch {
            [void][System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Não foi possível salvar', 'OK', 'Warning')
        } finally { $dialog.Dispose() }
    })
$combo.Add_SelectedIndexChanged({ if (-not $script:Suppress -and -not $script:Busy) { try { Show-SelectedReport } catch { $statusLabel.Text = $_.Exception.Message } } })
$monitor.Add_CheckedChanged({ $timer.Enabled = $monitor.Checked })
$timer.Add_Tick({ if ($monitor.Checked -and -not $script:Busy) { Invoke-UiAction 'Acompanhando o link...' { Update-Inventory } } })
$form.Add_Shown({ Invoke-UiAction 'Consultando a Ethernet...' { Update-Inventory } })
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })

[void]$form.ShowDialog()
$form.Dispose()
