# Permissões e segurança

Este documento detalha o que o SyncCheck acessa, com qual permissão, e o que ele **não** faz.

## Resumo

| Pergunta | Resposta |
|---|---|
| Precisa de Domain Admin? | **Não.** Uma conta comum do domínio é suficiente na maioria dos ambientes. |
| Altera algo no AD? | **Não.** Só usa cmdlets de leitura (`Get-ADUser`, `Get-ADGroup`, `Get-ADObject`, `Get-ADDomain`, `Get-ADForest`, `Get-ADRootDSE`). |
| Precisa de acesso ao Microsoft 365/Entra ID? | **Não.** A ferramenta não se conecta à nuvem. |
| Envia dados para algum lugar? | **Não.** Os relatórios são gravados apenas na pasta local de saída. |
| Precisa ser executado como administrador local? | **Não**, exceto para instalar o módulo ActiveDirectory (RSAT) ou instalar o SyncCheck para todos os usuários. |

## Permissões no Active Directory

A ferramenta faz apenas leitura. Os atributos consultados são:

| Objeto | Atributos |
|---|---|
| Usuários | `userPrincipalName`, `sAMAccountName`, `mail`, `proxyAddresses`, `displayName`, `givenName`, `sn`, `mailNickname`, `isCriticalSystemObject` |
| Grupos | `sAMAccountName`, `mail`, `proxyAddresses`, `displayName`, `mailNickname`, `member` (somente com `-GroupName`), `isCriticalSystemObject` |
| Contatos | `name`, `mail`, `proxyAddresses`, `displayName`, `mailNickname` |
| Domínio e floresta | nome DNS, NetBIOS, níveis funcionais, sufixos UPN |
| Esquema | presença dos atributos `proxyAddresses` e `mailNickname` |

Na configuração padrão do Active Directory, usuários autenticados do domínio conseguem ler esses atributos. Por isso, **uma conta comum do domínio costuma ser suficiente**, e é a recomendação, seguindo o princípio do menor privilégio.

### Quando uma conta comum pode não bastar

Alguns ambientes endurecidos restringem a leitura de objetos ou atributos, por exemplo:

- permissões de leitura removidas de "Authenticated Users" em OUs específicas;
- OUs com herança de permissões desabilitada;
- modo "List Object" habilitado no `dSHeuristics`.

O sintoma é um resultado incompleto: menos objetos do que o esperado, ou atributos como `mail` e `proxyAddresses` aparecendo vazios em massa. Nesse caso, rode com uma conta que tenha leitura em todo o domínio. Uma boa referência é a mesma conta usada pelo conector AD DS do Entra Connect, que precisa exatamente dessa leitura para sincronizar:

```powershell
Invoke-SyncCheck -Credential (Get-Credential)
```

## Rede

O módulo ActiveDirectory do PowerShell se comunica com o **Active Directory Web Services (ADWS)** do controlador de domínio:

| Porta | Protocolo | Uso |
|---|---|---|
| 9389 | TCP | Active Directory Web Services |

Se o `Get-ADDomain` falhar com "Unable to contact the server", verifique se a porta 9389 está liberada até o DC e se o serviço "Active Directory Web Services" está em execução nele.

## Execução no computador local

| Item | Necessidade |
|---|---|
| Pasta de saída | Permissão de escrita em `-OutputFolder` (padrão `C:\Temp\SyncCheck`). A pasta é criada se não existir. |
| Política de execução | `RemoteSigned` ou mais permissiva. O módulo **não é assinado digitalmente**, então em ambientes com `AllSigned` ele não vai carregar. |
| Arquivos baixados pelo navegador | Rode `Unblock-File` nos arquivos para evitar o aviso de segurança. Instalando pelo `Install-Module`, isso não é necessário. |

Para conferir a política atual:

```powershell
Get-ExecutionPolicy -List
```

Se precisar liberar só para o usuário atual:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Conteúdo dos relatórios

O CSV e o HTML contêm nomes de usuários, logins, endereços de e-mail e caminhos (DN) do AD. Trate esses arquivos como dados pessoais: guarde em local com acesso restrito, não publique em issues ou fóruns e apague-os ao fim do trabalho.

## Auditoria do código

O código está inteiro em um único arquivo, `src/SyncCheck/SyncCheck.psm1`, sem dependências externas, downloads ou binários. Para confirmar que não há operações de escrita no AD:

```powershell
Select-String -Path .\SyncCheck.psm1 -Pattern 'Set-AD|New-AD|Remove-AD|Add-AD|Rename-AD|Move-AD'
```

O comando não deve retornar nenhum resultado.
