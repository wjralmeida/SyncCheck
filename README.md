# SyncCheck

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/SyncCheck?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/SyncCheck)
[![Downloads](https://img.shields.io/powershellgallery/dt/SyncCheck)](https://www.powershellgallery.com/packages/SyncCheck)
[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue.svg)](LICENSE)

Diagnóstico **somente leitura** do Active Directory antes de sincronizar com o Microsoft Entra ID, via Entra Connect Sync ou Entra Cloud Sync.

O SyncCheck avalia usuários, grupos e contatos contra as regras que mais causam erro de sincronização ou perda de dados: UPN com sufixo `.local`, caracteres inválidos, `proxyAddresses` inconsistente, endereços duplicados entre objetos e limites de tamanho. O resultado sai em CSV e num relatório HTML pronto para análise.

Nasceu como alternativa gratuita e de código aberto às verificações que o IdFix fazia.

> **English summary:** read-only PowerShell module that checks Active Directory objects for issues that break or degrade Microsoft Entra ID synchronization (IdFix-style checks) and generates CSV and HTML reports. Reports are currently in Brazilian Portuguese.

---

## O que a ferramenta faz

- Lê os usuários habilitados, os grupos e os contatos do domínio. Também pode limitar a uma OU ou aos membros de um grupo.
- Aplica 25 regras de validação, classificadas como **Erro** (impede ou corrompe a sincronização do objeto) ou **Aviso** (risco de perda de dados ou inconsistência). Veja a lista completa em [docs/REGRAS.md](docs/REGRAS.md).
- Detecta automaticamente os sufixos UPN roteáveis cadastrados no AD e verifica se o esquema do Exchange foi estendido.
- Sugere o valor corrigido para cada item, por exemplo `maria.conceição@empresa.local` → `maria.conceicao@empresa.com.br`.
- Gera dois arquivos na pasta de saída:
  - `SyncCheck_<CLIENTE>_<data>.csv`: um item por linha, separado por `;`, abre direto no Excel em pt-BR;
  - `SyncCheck_<CLIENTE>_<data>.html`: relatório com resumo, ambiente, sufixos, resumo por regra e lista filtrável.

Veja um [relatório de exemplo](docs/exemplo/relatorio-exemplo.html), gerado com dados fictícios. Baixe o arquivo e abra no navegador.

## O que a ferramenta **não** faz

- **Não altera nada no AD.** Todas as operações são consultas (`Get-*`). Não existe nenhum comando de escrita no código.
- **Não se conecta ao Microsoft 365 ou ao Entra ID** e não envia dados para fora do ambiente. Tudo fica na pasta de saída local.
- **Não substitui o staging mode do Entra Connect.** Ela antecipa os problemas do lado do AD, mas não compara com os objetos que já existem na nuvem.

## Pré-requisitos

| Item | Requisito |
|---|---|
| Sistema operacional | Windows Server 2012 R2 ou superior, ou Windows 10/11 |
| PowerShell | Windows PowerShell 5.1 ou PowerShell 7.x (no Windows) |
| Módulo ActiveDirectory | RSAT: AD DS (veja abaixo) |
| Rede | Acesso a um controlador de domínio na porta **TCP 9389** (Active Directory Web Services) |
| Permissão | Conta de usuário comum do domínio (detalhes em [docs/PERMISSOES.md](docs/PERMISSOES.md)) |

**Instalar o módulo ActiveDirectory:**

```powershell
# Windows Server
Install-WindowsFeature RSAT-AD-PowerShell

# Windows 10/11
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

Em controladores de domínio o módulo já vem instalado.

## Instalação

### Pela PowerShell Gallery (recomendado)

```powershell
Install-Module SyncCheck -Scope CurrentUser
```

Para atualizar depois: `Update-Module SyncCheck`.

Em servidores mais antigos (2012 R2/2016), se o `Install-Module` falhar com erro de conexão, habilite o TLS 1.2 na sessão e tente de novo:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### Servidor sem acesso à internet

Em uma máquina com internet:

```powershell
Save-Module SyncCheck -Path C:\Temp\Modulos
```

Copie a pasta `C:\Temp\Modulos\SyncCheck` para `C:\Program Files\WindowsPowerShell\Modules\` no servidor de destino.

### Manual (pelo GitHub)

Baixe o `.zip` da [última release](../../releases/latest), extraia e importe:

```powershell
Unblock-File -Path .\SyncCheck\* 
Import-Module .\SyncCheck\SyncCheck.psd1
```

O `Unblock-File` remove a marca de "arquivo baixado da internet", que senão gera o aviso de segurança a cada execução.

## Uso

```powershell
# Tudo automático: domínio atual, sufixos roteáveis detectados no AD
Invoke-SyncCheck

# Informar os sufixos válidos e abrir o relatório ao final
Invoke-SyncCheck -UpnSuffix empresa.com.br,empresa.net -OpenReport

# Somente os membros diretos de um grupo (mesmo critério do filtro por grupo do Entra Connect)
Invoke-SyncCheck -GroupName G_Sync_Piloto

# Somente uma OU, incluindo usuários desabilitados
Invoke-SyncCheck -SearchBase "OU=Usuarios,DC=empresa,DC=local" -IncludeDisabled

# Outro domínio ou máquina fora do domínio
Invoke-SyncCheck -Server dc01.empresa.local -Credential (Get-Credential)

# Usar o resultado no pipeline
Invoke-SyncCheck -PassThru | Where-Object Regra -eq 'DUP-001' | Export-Csv duplicados.csv
```

### Parâmetros

| Parâmetro | Descrição | Padrão |
|---|---|---|
| `-Cliente` | Nome exibido no relatório e usado no nome dos arquivos | NetBIOS do domínio |
| `-UpnSuffix` | Sufixos UPN considerados válidos para a nuvem | Sufixos roteáveis cadastrados no AD |
| `-Server` | DC ou domínio a consultar | Domínio da máquina atual |
| `-Credential` | Credencial alternativa | Usuário atual |
| `-SearchBase` | Limita a uma OU (DN completo) | Domínio inteiro |
| `-GroupName` | Limita aos membros diretos de um grupo | — |
| `-IncludeDisabled` | Inclui usuários desabilitados | Desabilitados ignorados |
| `-OutputFolder` | Pasta de saída | `C:\Temp\SyncCheck` |
| `-OpenReport` | Abre o HTML ao final | — |
| `-PassThru` | Devolve os itens como objetos no pipeline | — |

Ajuda completa no próprio PowerShell: `Get-Help Invoke-SyncCheck -Full`.

## Como ler o resultado

- **Erro:** o objeto vai falhar na sincronização, ser criado com dados errados (por exemplo, com UPN `@tenant.onmicrosoft.com`) ou conflitar com outro objeto. Corrija antes de sincronizar.
- **Aviso:** o objeto sincroniza, mas existe risco de perda de dados ou comportamento inesperado. O caso mais comum é `proxyAddresses` vazio em quem já tem caixa na nuvem, o que faz os aliases existentes serem perdidos. Revise caso a caso.
- **Sugestão:** é indicativa, gerada automaticamente. Revise antes de aplicar, principalmente quando envolver troca de UPN, que muda o login do usuário.

A descrição de cada regra, com o motivo e a forma de correção, está em [docs/REGRAS.md](docs/REGRAS.md).

## Limitações conhecidas

- Avalia um domínio por execução. Para florestas com vários domínios, rode uma vez por domínio com `-Server`.
- A checagem de duplicidade considera os objetos do domínio consultado. Ela não enxerga outros domínios da floresta nem objetos que existem apenas na nuvem.
- O filtro `-GroupName` considera só membros diretos, igual ao Entra Connect. Grupos aninhados não são expandidos.
- Atributos que não existem no esquema (como `mailNickname` sem o esquema do Exchange) são detectados e as regras correspondentes são puladas.

## Privacidade (LGPD)

Os relatórios contêm nomes, logins e endereços de e-mail, que são dados pessoais. Armazene e compartilhe esses arquivos apenas com quem precisa deles e apague-os ao fim do projeto.

## Contribuindo

Sugestões de regras, correções e relatos de problemas são bem-vindos pelas [Issues](../../issues). Ao relatar um problema, informe a versão (`(Get-Module SyncCheck).Version`), a versão do PowerShell (`$PSVersionTable.PSVersion`) e a mensagem de erro completa. **Não anexe relatórios com dados reais.**

## Aviso

Projeto pessoal e de estudos, distribuído sem garantia sob a [licença MIT](LICENSE). Não é afiliado nem endossado pela Microsoft. Microsoft, Active Directory, Entra e Microsoft 365 são marcas da Microsoft Corporation.

---

Criado por **Wilson Neves de Almeida Junior**.
