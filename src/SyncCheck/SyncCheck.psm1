# SyncCheck - Active Directory readiness check for Microsoft Entra ID sync
# Copyright (c) 2026 Wilson Neves de Almeida Junior - MIT License
# https://github.com/wjralmeida/SyncCheck
#
# Observacao: este arquivo e 100% ASCII de proposito. Textos acentuados ficam como
# entidades HTML e sao convertidos em tempo de execucao pela funcao D, para o modulo
# funcionar em qualquer codificacao/idioma do Windows PowerShell 5.1.

function Invoke-SyncCheck {
<#
.SYNOPSIS
    Avalia a prontidao do Active Directory para sincronizacao com o Microsoft Entra ID
    (Entra Connect Sync ou Entra Cloud Sync).

.DESCRIPTION
    Ferramenta somente leitura: nao altera nenhum objeto do AD e nao envia dados para fora
    do ambiente. Avalia usuarios, grupos e contatos contra regras que causam erro de
    sincronizacao ou perda de dados (UPN, mail, proxyAddresses, duplicidades, caracteres
    invalidos e limites de tamanho) e gera um relatorio CSV e um HTML.

    Documentacao completa: https://github.com/wjralmeida/SyncCheck

.PARAMETER Cliente
    Nome usado no relatorio e no nome dos arquivos. Padrao: NetBIOS do dominio.

.PARAMETER UpnSuffix
    Sufixos UPN considerados validos para a nuvem. Padrao: sufixos roteaveis cadastrados no AD.

.PARAMETER Server
    Controlador de dominio ou dominio a consultar. Padrao: dominio da maquina atual.

.PARAMETER Credential
    Credencial alternativa para consultar o AD.

.PARAMETER SearchBase
    Limita a avaliacao a uma OU (DN completo).

.PARAMETER GroupName
    Limita a avaliacao aos membros diretos de um grupo, como no filtro por grupo do Entra Connect.

.PARAMETER IncludeDisabled
    Inclui usuarios desabilitados na avaliacao.

.PARAMETER OutputFolder
    Pasta de saida dos relatorios. Padrao: C:\Temp\SyncCheck

.PARAMETER OpenReport
    Abre o relatorio HTML ao final.

.PARAMETER PassThru
    Devolve os itens avaliados como objetos no pipeline.

.EXAMPLE
    Invoke-SyncCheck
    Detecta dominio, nome e sufixos UPN roteaveis automaticamente.

.EXAMPLE
    Invoke-SyncCheck -UpnSuffix empresa.com.br,empresa.net -OpenReport

.EXAMPLE
    Invoke-SyncCheck -GroupName G_Sync_Piloto

.EXAMPLE
    Invoke-SyncCheck -SearchBase "OU=Usuarios,DC=empresa,DC=local" -IncludeDisabled

.EXAMPLE
    Invoke-SyncCheck -Server dc01.empresa.local -Credential (Get-Credential)

.EXAMPLE
    Invoke-SyncCheck -PassThru | Where-Object Regra -eq 'DUP-001'

.LINK
    https://github.com/wjralmeida/SyncCheck
#>

    [CmdletBinding()]
    param(
        [string]       $Cliente,
        [string[]]     $UpnSuffix,
        [string]       $Server,
        [pscredential] $Credential,
        [string]       $SearchBase,
        [string]       $GroupName,
        [switch]       $IncludeDisabled,
        [string]       $OutputFolder = 'C:\Temp\SyncCheck',
        [switch]       $OpenReport,
        [switch]       $PassThru
    )


$ErrorActionPreference = 'Stop'

# Textos acentuados ficam como entidades HTML para o script ser 100% ASCII
function D([string]$s) { [System.Net.WebUtility]::HtmlDecode($s) }
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host (D "M&#243;dulo ActiveDirectory n&#227;o encontrado.") -ForegroundColor Red
    Write-Host "Servidor: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    Write-Host "Windows 10/11: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor Yellow
    return
}
Import-Module ActiveDirectory

$ToolVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { 'dev' }
$StartTime   = Get-Date
$Stamp       = $StartTime.ToString('yyyyMMdd_HHmm')

# Parametros de conexao repassados a todos os cmdlets do AD
$AD = @{}
if ($Server)     { $AD.Server     = $Server }
if ($Credential) { $AD.Credential = $Credential }

# ============================================================================
#  Catalogo de regras
# ============================================================================
$Rules = [ordered]@{
    'UPN-001' = @{ Sev = 'Erro';  Desc = 'UPN vazio' }
    'UPN-002' = @{ Sev = 'Erro';  Desc = 'Sufixo do UPN n&#227;o rote&#225;vel ou fora dos sufixos v&#225;lidos para a nuvem' }
    'UPN-003' = @{ Sev = 'Erro';  Desc = 'UPN com caractere inv&#225;lido (acento, espa&#231;o ou s&#237;mbolo)' }
    'UPN-004' = @{ Sev = 'Erro';  Desc = 'UPN com ponto no in&#237;cio, no fim ou duplicado antes do @' }
    'UPN-005' = @{ Sev = 'Erro';  Desc = 'Prefixo do UPN com mais de 64 caracteres' }
    'MAIL-001'= @{ Sev = 'Aviso'; Desc = 'Atributo mail vazio' }
    'MAIL-002'= @{ Sev = 'Erro';  Desc = 'Atributo mail com caractere ou formato inv&#225;lido' }
    'MAIL-003'= @{ Sev = 'Aviso'; Desc = 'Atributo mail diferente do UPN' }
    'PRX-001' = @{ Sev = 'Aviso'; Desc = 'proxyAddresses vazio: aliases existentes na nuvem podem ser perdidos' }
    'PRX-002' = @{ Sev = 'Erro';  Desc = 'proxyAddresses sem SMTP prim&#225;rio' }
    'PRX-003' = @{ Sev = 'Erro';  Desc = 'proxyAddresses com mais de um SMTP prim&#225;rio' }
    'PRX-004' = @{ Sev = 'Aviso'; Desc = 'SMTP prim&#225;rio diferente do atributo mail' }
    'PRX-005' = @{ Sev = 'Erro';  Desc = 'proxyAddresses com espa&#231;o ou caractere inv&#225;lido' }
    'PRX-006' = @{ Sev = 'Aviso'; Desc = 'proxyAddresses com dom&#237;nio n&#227;o rote&#225;vel (ser&#225; descartado na nuvem)' }
    'PRX-007' = @{ Sev = 'Aviso'; Desc = 'Endere&#231;o repetido dentro do pr&#243;prio objeto' }
    'DUP-001' = @{ Sev = 'Erro';  Desc = 'Endere&#231;o duplicado com outro objeto do AD' }
    'SAM-001' = @{ Sev = 'Erro';  Desc = 'sAMAccountName com caractere inv&#225;lido' }
    'SAM-002' = @{ Sev = 'Aviso'; Desc = 'sAMAccountName com mais de 20 caracteres' }
    'DSP-001' = @{ Sev = 'Aviso'; Desc = 'displayName vazio' }
    'DSP-002' = @{ Sev = 'Erro';  Desc = 'displayName com mais de 256 caracteres' }
    'NAM-001' = @{ Sev = 'Erro';  Desc = 'givenName ou sn com mais de 64 caracteres' }
    'NCK-001' = @{ Sev = 'Erro';  Desc = 'mailNickname com espa&#231;o, @ ou caractere inv&#225;lido' }
    'NCK-002' = @{ Sev = 'Erro';  Desc = 'mailNickname com mais de 64 caracteres' }
    'WSP-001' = @{ Sev = 'Aviso'; Desc = 'Espa&#231;o no in&#237;cio ou no fim do valor' }
    'EXE-001' = @{ Sev = 'Aviso'; Desc = 'Falha ao avaliar o objeto (verificar manualmente)' }
}

# Padroes
$rxLocalInvalid = '[^a-zA-Z0-9''.\-_!#^~]'                        # caracteres aceitos no prefixo do UPN/SMTP
$rxAddress      = '^[^@\s]+@[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)+$'
$rxNonRoutable  = '(\.(local|lan|internal|intra|corp|localdomain|home)$)|^[^.]+$'
$rxSamInvalid   = '["/\\\[\]:;|=,+*?<>@]'
$rxNickInvalid  = '[^a-zA-Z0-9!#$%&''*+\-/=?^_`{|}~.]'
$rxSkipAccounts = '^(MSOL_|AAD_|Sync_|HealthMailbox|SystemMailbox|FederatedEmail|DiscoverySearchMailbox|Migration\.|SUPPORT_388945a0|CAS_|krbtgt$|Guest$|Convidado$|DefaultAccount$|WDAGUtilityAccount$)'

# ============================================================================
#  Funcoes auxiliares
# ============================================================================
$Issues = New-Object System.Collections.Generic.List[object]

function Add-Issue {
    param($Rule, $Name, $Type, $DN, $Attr, $Value, $Fix = '')
    $r = $Rules[$Rule]
    $Issues.Add([pscustomobject]@{
        Severidade        = $r.Sev
        Regra             = $Rule
        Descricao         = D $r.Desc
        TipoObjeto        = D $Type
        Objeto            = $Name
        Atributo          = D $Attr
        Valor             = [string]$Value
        Sugestao          = D ([string]$Fix)
        DistinguishedName = $DN
    })
}

function ConvertTo-Ascii([string]$s) {
    if (-not $s) { return $s }
    $n  = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Get-CleanLocal([string]$s) {
    if (-not $s) { return $s }
    $x = (ConvertTo-Ascii $s.Trim()) -replace '\s+', '.'
    $x = $x -replace $rxLocalInvalid, '' -replace '\.{2,}', '.'
    $x.Trim('.')
}

function Test-InScope([string]$dn) {
    (-not $ScopeDNs) -or $ScopeDNs.Contains($dn)
}

function Test-Addresses {
    param($Name, $Type, $DN, $Mail, $Proxy, $Upn)

    # mail
    if ($Mail) {
        if ($Mail -ne $Mail.Trim()) {
            Add-Issue 'WSP-001' $Name $Type $DN 'mail' $Mail $Mail.Trim()
        }
        $m = $Mail.Trim()
        if ($m -notmatch $rxAddress -or $m.Split('@')[0] -match $rxLocalInvalid) {
            $fix = if ($m -match '@') { "$(Get-CleanLocal $m.Split('@')[0])@$($m.Split('@')[1])" } else { '' }
            Add-Issue 'MAIL-002' $Name $Type $DN 'mail' $Mail $fix
        }
        if ($Upn -and $m -ne $Upn) {
            Add-Issue 'MAIL-003' $Name $Type $DN 'mail' $Mail "UPN atual: $Upn"
        }
    }

    # proxyAddresses
    $smtp = @($Proxy | Where-Object { $_ -match '^smtp:' })
    if ($smtp.Count -eq 0) {
        if ($Mail) { Add-Issue 'PRX-001' $Name $Type $DN 'proxyAddresses' '(vazio)' "SMTP:$($Mail.Trim())" }
    } else {
        $primary = @($smtp | Where-Object { $_ -cmatch '^SMTP:' })
        if ($primary.Count -eq 0) {
            $fix = if ($Mail) { "SMTP:$($Mail.Trim())" } else { 'Definir um endere&#231;o como SMTP: (mai&#250;sculo)' }
            Add-Issue 'PRX-002' $Name $Type $DN 'proxyAddresses' ($smtp -join '; ') $fix
        } elseif ($primary.Count -gt 1) {
            Add-Issue 'PRX-003' $Name $Type $DN 'proxyAddresses' ($primary -join '; ') 'Manter apenas um SMTP: em mai&#250;sculo'
        } elseif ($Mail -and $primary[0].Substring(5) -ne $Mail.Trim()) {
            Add-Issue 'PRX-004' $Name $Type $DN 'proxyAddresses' $primary[0] "SMTP:$($Mail.Trim()) ou ajustar o mail"
        }

        $seen = @{}
        foreach ($p in $smtp) {
            $addr = $p.Substring(5)
            if ($addr -match '\s' -or $addr -notmatch $rxAddress -or $addr.Split('@')[0] -match $rxLocalInvalid) {
                Add-Issue 'PRX-005' $Name $Type $DN 'proxyAddresses' $p ''
            } elseif ($addr.Split('@')[1] -match $rxNonRoutable) {
                Add-Issue 'PRX-006' $Name $Type $DN 'proxyAddresses' $p 'Remover o endere&#231;o'
            }
            $k = $addr.Trim().ToLower()
            if ($seen.ContainsKey($k)) {
                Add-Issue 'PRX-007' $Name $Type $DN 'proxyAddresses' $p 'Remover a entrada repetida'
            } else { $seen[$k] = 1 }
        }
    }

    # Duplicidade com outros objetos
    $mine = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $smtp) { [void]$mine.Add($p.Substring(5).Trim()) }
    if ($Mail) { [void]$mine.Add($Mail.Trim()) }
    if ($Upn)  { [void]$mine.Add($Upn.Trim()) }
    foreach ($a in $mine) {
        $k = $a.ToLower()
        if ($AddrIndex.ContainsKey($k)) {
            $others = @($AddrIndex[$k] | Where-Object { $_ -ne $DN })
            if ($others.Count -gt 0) {
                Add-Issue 'DUP-001' $Name $Type $DN 'endere&#231;o' $a ("Tamb&#233;m em: " + ($others -join ' | '))
            }
        }
    }
}

function Test-Nickname($Name, $Type, $DN, $Nick) {
    if (-not $Nick) { return }
    if ($Nick -match '[\s@]' -or $Nick -match $rxNickInvalid -or $Nick -match '^\.|\.$') {
        Add-Issue 'NCK-001' $Name $Type $DN 'mailNickname' $Nick (Get-CleanLocal $Nick)
    }
    if ($Nick.Length -gt 64) {
        Add-Issue 'NCK-002' $Name $Type $DN 'mailNickname' $Nick $Nick.Substring(0, 64)
    }
}

function Get-HtmlSafe([object]$s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }

# ============================================================================
#  Coleta
# ============================================================================
Write-Host "SyncCheck $ToolVersion" -ForegroundColor Cyan
Write-Host (D "Coletando informa&#231;&#245;es do ambiente...") -ForegroundColor Gray

try {
    $Domain = Get-ADDomain @AD
} catch {
    Write-Host (D "N&#227;o foi poss&#237;vel consultar o dom&#237;nio: $($_.Exception.Message)") -ForegroundColor Red
    Write-Host (D "Verifique se a m&#225;quina est&#225; no dom&#237;nio ou use -Server e -Credential.") -ForegroundColor Yellow
    return
}
try {
    $Forest = Get-ADForest @AD
} catch {
    $Forest = [pscustomobject]@{ Name = $Domain.Forest; ForestMode = '(sem acesso)'; UPNSuffixes = @() }
}

if (-not $Cliente) { $Cliente = $Domain.NetBIOSName }
$SafeName = $Cliente -replace '[\\/:*?"<>|\s]', '_'
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$CsvPath  = Join-Path $OutputFolder "SyncCheck_${SafeName}_$Stamp.csv"
$HtmlPath = Join-Path $OutputFolder "SyncCheck_${SafeName}_$Stamp.html"

# Sufixos UPN: cadastrados na floresta + nome DNS do dominio
$ForestSuffixes = @(@($Forest.UPNSuffixes) + @($Domain.DNSRoot) | Where-Object { $_ } | Select-Object -Unique)
if ($UpnSuffix) {
    $SuffixSource = D 'Informados via -UpnSuffix'
} else {
    $UpnSuffix    = @($ForestSuffixes | Where-Object { $_ -notmatch $rxNonRoutable })
    $SuffixSource = D 'Detectados automaticamente (sufixos rote&#225;veis do AD)'
}
$UpnSuffix       = @($UpnSuffix | Where-Object { $_ })
$TargetSuffix    = if ($UpnSuffix.Count) { $UpnSuffix[0] } else { '<sufixo-roteavel>' }
$MissingSuffixes = @($UpnSuffix | Where-Object { $ForestSuffixes -notcontains $_ })
Write-Host (D "Cliente: $Cliente | Dom&#237;nio: $($Domain.DNSRoot)") -ForegroundColor Cyan

# Atributos opcionais: so consulta o que existe no esquema
# (mailNickname so existe com o esquema do Exchange estendido)
$SchemaNC = (Get-ADRootDSE @AD).schemaNamingContext
function Test-SchemaAttr([string]$name) {
    [bool](Get-ADObject -SearchBase $SchemaNC -LDAPFilter "(lDAPDisplayName=$name)" @AD)
}
$HasProxy = Test-SchemaAttr 'proxyAddresses'
$HasNick  = Test-SchemaAttr 'mailNickname'
$optProps = @()
if ($HasProxy) { $optProps += 'proxyAddresses' }
if ($HasNick)  { $optProps += 'mailNickname' }
$ExchangeSchema = if ($HasNick) { 'Estendido (atributos do Exchange presentes)' } else { 'N&#227;o estendido: mailNickname n&#227;o avaliado' }

# Escopo por grupo (membros diretos, igual ao filtro do Entra Connect)
$ScopeDNs = $null
if ($GroupName) {
    $grp = Get-ADGroup -Identity $GroupName -Properties member @AD
    $ScopeDNs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in $grp.member) { [void]$ScopeDNs.Add($m) }
}

$sbParams = $AD.Clone()
if ($SearchBase) { $sbParams.SearchBase = $SearchBase }

# Indice global de enderecos (dominio inteiro) para detectar duplicidade
Write-Host (D "Indexando endere&#231;os do dom&#237;nio...") -ForegroundColor Gray
$AddrIndex = @{}
$idxFilter = if ($HasProxy) { '(|(proxyAddresses=*)(mail=*)(userPrincipalName=*))' } else { '(|(mail=*)(userPrincipalName=*))' }
Get-ADObject -LDAPFilter $idxFilter `
    -Properties (@('mail', 'userPrincipalName') + $optProps) -ResultSetSize $null @AD |
ForEach-Object {
    $o   = $_
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $o.proxyAddresses) { if ($p -match '^smtp:') { [void]$set.Add($p.Substring(5).Trim()) } }
    if ($o.mail)              { [void]$set.Add($o.mail.Trim()) }
    if ($o.userPrincipalName) { [void]$set.Add($o.userPrincipalName.Trim()) }
    foreach ($a in $set) {
        $k = $a.ToLower()
        if (-not $AddrIndex.ContainsKey($k)) { $AddrIndex[$k] = New-Object System.Collections.Generic.List[string] }
        $AddrIndex[$k].Add($o.DistinguishedName)
    }
}

Write-Host (D "Coletando usu&#225;rios, grupos e contatos...") -ForegroundColor Gray
$userFilter = if ($IncludeDisabled) { '*' } else { 'Enabled -eq $true' }
$userProps  = @('UserPrincipalName','SamAccountName','mail','DisplayName','GivenName',
               'Surname','isCriticalSystemObject') + $optProps

$AllUsers = @(Get-ADUser -Filter $userFilter -Properties $userProps @sbParams)
$Skipped  = @($AllUsers | Where-Object { $_.isCriticalSystemObject -or $_.SamAccountName -match $rxSkipAccounts }).Count
$Users    = @($AllUsers | Where-Object {
    -not ($_.isCriticalSystemObject -or $_.SamAccountName -match $rxSkipAccounts) -and (Test-InScope $_.DistinguishedName)
})

$Groups = @(Get-ADGroup -Filter * -Properties (@('mail', 'displayName', 'isCriticalSystemObject') + $optProps) @sbParams |
    Where-Object { -not $_.isCriticalSystemObject -and (Test-InScope $_.DistinguishedName) })

$Contacts = @(Get-ADObject -LDAPFilter '(objectClass=contact)' -Properties (@('mail', 'displayName') + $optProps) @sbParams |
    Where-Object { Test-InScope $_.DistinguishedName })

# ============================================================================
#  Avaliacao
# ============================================================================
Write-Host (D "Avaliando $($Users.Count) usu&#225;rios, $($Groups.Count) grupos e $($Contacts.Count) contatos...") -ForegroundColor Gray

foreach ($u in $Users) {
    $n = $u.SamAccountName; $dn = $u.DistinguishedName; $t = 'Usu&#225;rio'
    try {
    $upn = $u.UserPrincipalName

    if (-not $upn) {
        Add-Issue 'UPN-001' $n $t $dn 'userPrincipalName' '(vazio)' "$(Get-CleanLocal $n)@$TargetSuffix"
    } else {
        $parts = $upn.Split('@')
        if ($parts.Count -ne 2) {
            Add-Issue 'UPN-003' $n $t $dn 'userPrincipalName' $upn ''
        } else {
            $local = $parts[0]; $dom = $parts[1]
            if (($UpnSuffix -notcontains $dom) -or ($dom -match $rxNonRoutable)) {
                Add-Issue 'UPN-002' $n $t $dn 'userPrincipalName' $upn "$(Get-CleanLocal $local)@$TargetSuffix"
            }
            if ($local -match $rxLocalInvalid) {
                Add-Issue 'UPN-003' $n $t $dn 'userPrincipalName' $upn "$(Get-CleanLocal $local)@$dom"
            } elseif ($local -match '^\.|\.$|\.\.') {
                Add-Issue 'UPN-004' $n $t $dn 'userPrincipalName' $upn "$(Get-CleanLocal $local)@$dom"
            }
            if ($local.Length -gt 64) {
                Add-Issue 'UPN-005' $n $t $dn 'userPrincipalName' $upn ''
            }
        }
    }

    if (-not $u.mail) { Add-Issue 'MAIL-001' $n $t $dn 'mail' '(vazio)' $(if ($upn -and $upn -match '@') { "$(Get-CleanLocal $upn.Split('@')[0])@$TargetSuffix" }) }
    Test-Addresses -Name $n -Type $t -DN $dn -Mail $u.mail -Proxy $u.proxyAddresses -Upn $upn

    if ($n -match $rxSamInvalid) { Add-Issue 'SAM-001' $n $t $dn 'sAMAccountName' $n '' }
    if ($n.Length -gt 20)        { Add-Issue 'SAM-002' $n $t $dn 'sAMAccountName' $n '' }

    if (-not $u.DisplayName) {
        Add-Issue 'DSP-001' $n $t $dn 'displayName' '(vazio)' (("$($u.GivenName) $($u.Surname)").Trim())
    } elseif ($u.DisplayName.Length -gt 256) {
        Add-Issue 'DSP-002' $n $t $dn 'displayName' $u.DisplayName ''
    } elseif ($u.DisplayName -ne $u.DisplayName.Trim()) {
        Add-Issue 'WSP-001' $n $t $dn 'displayName' $u.DisplayName $u.DisplayName.Trim()
    }

    foreach ($attr in 'GivenName', 'Surname') {
        $v = $u.$attr
        if ($v) {
            if ($v.Length -gt 64)       { Add-Issue 'NAM-001' $n $t $dn $attr $v $v.Substring(0, 64) }
            elseif ($v -ne $v.Trim())   { Add-Issue 'WSP-001' $n $t $dn $attr $v $v.Trim() }
        }
    }

    Test-Nickname $n $t $dn $u.mailNickname
    } catch { Add-Issue 'EXE-001' $n $t $dn '' $_.Exception.Message '' }
}

foreach ($g in $Groups) {
    $n = $g.SamAccountName; $dn = $g.DistinguishedName; $t = 'Grupo'
    try {
    Test-Addresses -Name $n -Type $t -DN $dn -Mail $g.mail -Proxy $g.proxyAddresses -Upn $null
    if ($n -match $rxSamInvalid) { Add-Issue 'SAM-001' $n $t $dn 'sAMAccountName' $n '' }
    if ($g.displayName -and $g.displayName.Length -gt 256) { Add-Issue 'DSP-002' $n $t $dn 'displayName' $g.displayName '' }
    Test-Nickname $n $t $dn $g.mailNickname
    } catch { Add-Issue 'EXE-001' $n $t $dn '' $_.Exception.Message '' }
}

foreach ($c in $Contacts) {
    $n = $c.Name; $dn = $c.DistinguishedName; $t = 'Contato'
    try {
    Test-Addresses -Name $n -Type $t -DN $dn -Mail $c.mail -Proxy $c.proxyAddresses -Upn $null
    if (-not $c.displayName) { Add-Issue 'DSP-001' $n $t $dn 'displayName' '(vazio)' $n }
    Test-Nickname $n $t $dn $c.mailNickname
    } catch { Add-Issue 'EXE-001' $n $t $dn '' $_.Exception.Message '' }
}

# ============================================================================
#  Consolidacao
# ============================================================================
$Evaluated   = $Users.Count + $Groups.Count + $Contacts.Count
$ErrDNs      = @($Issues | Where-Object Severidade -eq 'Erro'  | Select-Object -ExpandProperty DistinguishedName -Unique)
$AllDNs      = @($Issues | Select-Object -ExpandProperty DistinguishedName -Unique)
$ObjErr      = $ErrDNs.Count
$ObjWarn     = $AllDNs.Count - $ObjErr
$ObjOk       = $Evaluated - $AllDNs.Count

$Sorted = $Issues | Sort-Object @{ Expression = { if ($_.Severidade -eq 'Erro') { 0 } else { 1 } } }, Regra, Objeto

if ($Issues.Count -gt 0) {
    $Sorted | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
}

$ByRule = $Issues | Group-Object Regra | ForEach-Object {
    [pscustomobject]@{
        Regra      = $_.Name
        Severidade = $Rules[$_.Name].Sev
        Descricao  = D $Rules[$_.Name].Desc
        Ocorrencias= $_.Count
        Objetos    = @($_.Group | Select-Object -ExpandProperty DistinguishedName -Unique).Count
    }
} | Sort-Object @{ Expression = { if ($_.Severidade -eq 'Erro') { 0 } else { 1 } } }, @{ Expression = 'Ocorrencias'; Descending = $true }

# ============================================================================
#  Relatorio HTML
# ============================================================================
$Scope = D $(if ($GroupName) { "Membros diretos do grupo $GroupName" }
         elseif ($SearchBase) { "OU $SearchBase" }
         else { 'Dom&#237;nio inteiro' })

if ($ObjErr -gt 0) {
    $Headline = D "$ObjErr de $Evaluated objetos precisam de ajuste antes da sincroniza&#231;&#227;o"
} elseif ($ObjWarn -gt 0) {
    $Headline = D "Nenhum erro bloqueante. $ObjWarn objetos t&#234;m pontos de melhoria a revisar"
} else {
    $Headline = D "Todos os $Evaluated objetos avaliados est&#227;o prontos para sincronizar"
}

$pctOk   = if ($Evaluated) { [math]::Round(100 * $ObjOk   / $Evaluated, 1) } else { 0 }
$pctWarn = if ($Evaluated) { [math]::Round(100 * $ObjWarn / $Evaluated, 1) } else { 0 }
$pctErr  = if ($Evaluated) { [math]::Round(100 * $ObjErr  / $Evaluated, 1) } else { 0 }
$inv = [Globalization.CultureInfo]::InvariantCulture

$allSuffixes = @(@($ForestSuffixes) + @($UpnSuffix) | Select-Object -Unique)
$suffixRows = foreach ($s in $allSuffixes) {
    $routable = $s -notmatch $rxNonRoutable
    $inForest = $ForestSuffixes -contains $s
    $used     = $UpnSuffix -contains $s
    $tipo = if ($routable) { 'Rote&#225;vel' } else { 'N&#227;o rote&#225;vel' }
    $st = if (-not $inForest)  { '<span class="pill Erro">N&#227;o cadastrado no AD</span>' }
          elseif ($used)       { '<span class="pill ok">V&#225;lido para a nuvem</span>' }
          elseif (-not $routable) { '<span class="pill Aviso">N&#227;o sincroniza como UPN</span>' }
          else                 { '<span class="pill Aviso">N&#227;o inclu&#237;do na avalia&#231;&#227;o</span>' }
    "<tr><td>$(Get-HtmlSafe $s)</td><td>$tipo</td><td>$st</td></tr>"
}
if ($UpnSuffix.Count -eq 0) {
    $suffixRows = @('<tr><td colspan="3"><span class="pill Erro">Nenhum sufixo rote&#225;vel cadastrado no AD</span> Cadastre o dom&#237;nio p&#250;blico em Active Directory Domains and Trusts ou informe -UpnSuffix.</td></tr>') + @($suffixRows)
}

$ruleRows = foreach ($r in $ByRule) {
    "<tr><td><span class=""pill $($r.Severidade)"">$($r.Severidade)</span></td><td class=""code"">$($r.Regra)</td><td>$(Get-HtmlSafe $r.Descricao)</td><td class=""num"">$($r.Objetos)</td><td class=""num"">$($r.Ocorrencias)</td></tr>"
}

$detailRows = foreach ($i in $Sorted) {
    "<tr data-sev=""$($i.Severidade)""><td><span class=""pill $($i.Severidade)"">$($i.Severidade)</span></td><td class=""code"">$($i.Regra)</td><td>$(Get-HtmlSafe $i.TipoObjeto)</td><td title=""$(Get-HtmlSafe $i.DistinguishedName)""><strong>$(Get-HtmlSafe $i.Objeto)</strong></td><td>$(Get-HtmlSafe $i.Descricao)</td><td>$(Get-HtmlSafe $i.Atributo)</td><td class=""code"">$(Get-HtmlSafe $i.Valor)</td><td class=""code"">$(Get-HtmlSafe $i.Sugestao)</td></tr>"
}

$css = @'
:root{--ink:#14324a;--paper:#f6f7f5;--sheet:#fff;--line:#d8ddd8;--text:#1e2a33;--muted:#5c6a74;--err:#b3261e;--errbg:#fbe9e7;--warn:#8a5a00;--warnbg:#fff3d6;--ok:#2e7d4f;--okbg:#e6f3eb}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--text);font:15px/1.5 "Segoe UI",Calibri,Arial,sans-serif}
header{background:var(--ink);color:#fff;padding:32px 40px 28px}
header .meta{opacity:.75;font-size:13px;margin:0 0 14px}
header h1{margin:0;font-size:30px;line-height:1.2;font-weight:600;max-width:900px}
.bar{display:flex;height:10px;border-radius:5px;overflow:hidden;margin:22px 0 10px;max-width:900px;background:rgba(255,255,255,.15)}
.bar span{display:block}.bar .e{background:#e5675e}.bar .w{background:#e8b04b}.bar .o{background:#6cc08f}
.legend{display:flex;gap:24px;flex-wrap:wrap;font-size:13px;opacity:.9}
.legend b{font-size:18px;font-weight:600;margin-right:4px}
main{max-width:1400px;margin:0 auto;padding:28px 40px 40px}
section{background:var(--sheet);border:1px solid var(--line);border-radius:6px;padding:22px 24px;margin-bottom:22px}
h2{font-size:18px;margin:0 0 4px;color:var(--ink)}
.lead{color:var(--muted);margin:0 0 16px;font-size:14px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:22px}
.tw{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:14px}
th{text-align:left;font-weight:600;color:var(--muted);font-size:13px;padding:8px 10px;border-bottom:2px solid var(--line);white-space:nowrap}
td{padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
tr:last-child td{border-bottom:0}
td.num{text-align:right;font-variant-numeric:tabular-nums}
td.code{font-family:Consolas,"Cascadia Mono",monospace;font-size:13px;word-break:break-all}
.kv td:first-child{color:var(--muted);width:42%}
.pill{display:inline-block;padding:1px 9px;border-radius:9px;font-size:12px;font-weight:600;white-space:nowrap}
.pill.Erro{background:var(--errbg);color:var(--err)}.pill.Aviso{background:var(--warnbg);color:var(--warn)}.pill.ok{background:var(--okbg);color:var(--ok)}
.tools{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:14px}
.tools input,.tools select{font:inherit;padding:7px 10px;border:1px solid var(--line);border-radius:5px;background:#fff}
.tools input{flex:1;min-width:240px}
.tools input:focus,.tools select:focus{outline:2px solid var(--ink);outline-offset:1px}
.count{color:var(--muted);font-size:13px;align-self:center}
.empty{color:var(--muted);padding:12px 0}
footer{color:var(--muted);font-size:12px;text-align:center;padding:0 0 28px}
@media (max-width:700px){header{padding:24px 20px}main{padding:20px}header h1{font-size:24px}}
@media print{body{background:#fff}.tools{display:none}header,.bar span,.pill{-webkit-print-color-adjust:exact;print-color-adjust:exact}section{break-inside:avoid-page}}
'@

$js = @'
function filtrar(){
  var q=document.getElementById('q').value.toLowerCase();
  var s=document.getElementById('sev').value;
  var n=0;
  document.querySelectorAll('#det tbody tr').forEach(function(r){
    var show=r.textContent.toLowerCase().indexOf(q)>-1 && (!s || r.getAttribute('data-sev')===s);
    r.style.display=show?'':'none'; if(show){n++;}
  });
  document.getElementById('cnt').textContent=n+' itens exibidos';
}
'@

$detailSection = if ($Issues.Count -gt 0) {
@"
<div class="tools">
  <input id="q" type="search" placeholder="Filtrar por objeto, regra, atributo ou valor" oninput="filtrar()" aria-label="Filtrar itens">
  <select id="sev" onchange="filtrar()" aria-label="Severidade">
    <option value="">Todas as severidades</option><option value="Erro">Somente erros</option><option value="Aviso">Somente avisos</option>
  </select>
  <span class="count" id="cnt">$($Issues.Count) itens exibidos</span>
</div>
<div class="tw"><table id="det">
<thead><tr><th>Severidade</th><th>Regra</th><th>Tipo</th><th>Objeto</th><th>Descri&#231;&#227;o</th><th>Atributo</th><th>Valor atual</th><th>Sugest&#227;o</th></tr></thead>
<tbody>
$($detailRows -join "`n")
</tbody></table></div>
"@
} else { '<p class="empty">Nenhum ponto de melhoria identificado no escopo avaliado.</p>' }

$ruleSection = if ($ByRule) {
@"
<div class="tw"><table>
<thead><tr><th>Severidade</th><th>Regra</th><th>Descri&#231;&#227;o</th><th>Objetos</th><th>Ocorr&#234;ncias</th></tr></thead>
<tbody>$($ruleRows -join "`n")</tbody></table></div>
"@
} else { '<p class="empty">Nenhuma regra disparada.</p>' }

$html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SyncCheck - $(Get-HtmlSafe $Cliente)</title>
<style>$css</style>
</head>
<body>
<header>
  <p class="meta">Prontid&#227;o para Microsoft Entra Connect &nbsp;|&nbsp; $(Get-HtmlSafe $Cliente) &nbsp;|&nbsp; $($Domain.DNSRoot) &nbsp;|&nbsp; $($StartTime.ToString('dd/MM/yyyy HH:mm'))</p>
  <h1>$(Get-HtmlSafe $Headline)</h1>
  <div class="bar" role="img" aria-label="Distribui&#231;&#227;o dos objetos avaliados">
    <span class="e" style="width:$($pctErr.ToString($inv))%"></span><span class="w" style="width:$($pctWarn.ToString($inv))%"></span><span class="o" style="width:$($pctOk.ToString($inv))%"></span>
  </div>
  <div class="legend">
    <span><b>$ObjErr</b> com erro</span>
    <span><b>$ObjWarn</b> somente com aviso</span>
    <span><b>$ObjOk</b> prontos</span>
    <span><b>$Evaluated</b> objetos avaliados</span>
  </div>
</header>
<main>
<div class="grid">
<section>
  <h2>Ambiente</h2>
  <p class="lead">Escopo e par&#226;metros usados nesta avalia&#231;&#227;o.</p>
  <table class="kv">
    <tr><td>Floresta</td><td>$($Forest.Name) ($($Forest.ForestMode))</td></tr>
    <tr><td>Dom&#237;nio</td><td>$($Domain.DNSRoot) / $($Domain.NetBIOSName) ($($Domain.DomainMode))</td></tr>
    <tr><td>Escopo</td><td>$(Get-HtmlSafe $Scope)</td></tr>
    <tr><td>Usu&#225;rios / grupos / contatos</td><td>$($Users.Count) / $($Groups.Count) / $($Contacts.Count)</td></tr>
    <tr><td>Contas de sistema ignoradas</td><td>$Skipped</td></tr>
    <tr><td>Esquema do Exchange</td><td>$ExchangeSchema</td></tr>
    <tr><td>Usu&#225;rios desabilitados</td><td>$(if ($IncludeDisabled) { 'Inclu&#237;dos' } else { 'N&#227;o avaliados' })</td></tr>
  </table>
</section>
<section>
  <h2>Sufixos UPN</h2>
  <p class="lead">$(Get-HtmlSafe $SuffixSource).</p>
  <table><thead><tr><th>Sufixo</th><th>Tipo</th><th>Situa&#231;&#227;o</th></tr></thead><tbody>$($suffixRows -join "`n")</tbody></table>
</section>
</div>
<section>
  <h2>Resumo por regra</h2>
  <p class="lead">Erros impedem ou corrompem a sincroniza&#231;&#227;o do objeto. Avisos indicam risco de perda de dados ou inconsist&#234;ncia.</p>
  $ruleSection
</section>
<section>
  <h2>Itens avaliados com pontos de melhoria</h2>
  <p class="lead">Passe o mouse sobre o objeto para ver o DN completo. As sugest&#245;es s&#227;o indicativas e devem ser revisadas antes de qualquer altera&#231;&#227;o.</p>
  $detailSection
</section>
</main>
<footer>Gerado por SyncCheck $ToolVersion em $($StartTime.ToString('dd/MM/yyyy HH:mm')) &nbsp;|&nbsp; github.com/wjralmeida/SyncCheck &nbsp;|&nbsp; Ferramenta somente leitura</footer>
<script>$js</script>
</body>
</html>
"@

$html | Out-File -FilePath $HtmlPath -Encoding UTF8

# ============================================================================
#  Resumo no console
# ============================================================================
Write-Host ""
Write-Host $Headline -ForegroundColor $(if ($ObjErr) { 'Red' } elseif ($ObjWarn) { 'Yellow' } else { 'Green' })
Write-Host ("  Com erro: {0}   Somente aviso: {1}   Prontos: {2}   Avaliados: {3}" -f $ObjErr, $ObjWarn, $ObjOk, $Evaluated)
Write-Host (D "  Sufixos v&#225;lidos: $(if ($UpnSuffix.Count) { $UpnSuffix -join ', ' } else { '(nenhum)' })  [$SuffixSource]") -ForegroundColor Gray
if ($UpnSuffix.Count -eq 0) {
    Write-Host (D "  ATEN&#199;&#195;O: nenhum sufixo rote&#225;vel no AD. Cadastre o dom&#237;nio p&#250;blico ou rode com -UpnSuffix dominio.com.br") -ForegroundColor Red
}
if ($MissingSuffixes.Count) {
    Write-Host (D "  ATEN&#199;&#195;O: sufixo(s) informado(s) e n&#227;o cadastrado(s) no AD: $($MissingSuffixes -join ', ')") -ForegroundColor Red
}
if ($ByRule) {
    Write-Host ""
    $ByRule | Format-Table Severidade, Regra, Descricao, Objetos, Ocorrencias -AutoSize | Out-String -Width 220 | Write-Host
}
Write-Host (D "Relat&#243;rio HTML: $HtmlPath") -ForegroundColor Green
if ($Issues.Count -gt 0) { Write-Host "CSV:            $CsvPath" -ForegroundColor Green }

if ($OpenReport) { Invoke-Item $HtmlPath }
if ($PassThru)   { $Sorted }

}

Export-ModuleMember -Function Invoke-SyncCheck
