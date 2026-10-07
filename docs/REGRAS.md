# Regras de validação

Cada item do relatório tem um identificador de regra estável (ex.: `UPN-002`), que não muda entre versões. A severidade indica o impacto:

- **Erro:** o objeto falha na sincronização, sobe com dados errados ou conflita com outro objeto.
- **Aviso:** o objeto sincroniza, mas há risco de perda de dados ou inconsistência.

Os caracteres aceitos no prefixo de UPN e de endereços SMTP são: `A-Z a-z 0-9 ' . - _ ! # ^ ~`.

---

## UPN (userPrincipalName)

O UPN vira o login do usuário no Microsoft 365. Se ele não usar um domínio verificado no tenant, o Entra ID troca o sufixo por `@<tenant>.onmicrosoft.com`. Além disso, o UPN é um dos critérios do soft match com contas que já existem na nuvem.

| Regra | Severidade | O que verifica | Como corrigir |
|---|---|---|---|
| `UPN-001` | Erro | UPN vazio | Definir um UPN com sufixo roteável. |
| `UPN-002` | Erro | Sufixo não roteável (`.local`, `.lan`, `.corp`…) ou fora da lista de sufixos válidos | Cadastrar o domínio público como sufixo alternativo em *Active Directory Domains and Trusts* e alterar o UPN do usuário. |
| `UPN-003` | Erro | Caracteres inválidos no prefixo (acentos, espaços, símbolos) | Remover os acentos e trocar espaços por ponto. |
| `UPN-004` | Erro | Ponto no início, no fim ou dois pontos seguidos antes do `@` | Ajustar o prefixo. |
| `UPN-005` | Erro | Prefixo com mais de 64 caracteres | Encurtar o prefixo. |

> **Atenção:** alterar o UPN muda o login do usuário. Comunique a troca antes, principalmente se o usuário já usa o Microsoft 365.

## mail

| Regra | Severidade | O que verifica | Como corrigir |
|---|---|---|---|
| `MAIL-001` | Aviso | Atributo `mail` vazio | Preencher com o endereço principal do usuário, se ele tiver caixa de correio. Para usuários sem e-mail, pode ser ignorado. |
| `MAIL-002` | Erro | Formato inválido ou caracteres não permitidos | Corrigir o endereço. |
| `MAIL-003` | Aviso | `mail` diferente do UPN | Não é obrigatório que sejam iguais, mas manter os dois iguais simplifica o login e evita confusão para o usuário. |

## proxyAddresses

Este atributo define todos os endereços de e-mail do objeto. `SMTP:` em maiúsculo indica o endereço primário, e `smtp:` em minúsculo indica os aliases. Quando o objeto passa a ser sincronizado, o AD vira a fonte dos endereços: o que não estiver em `proxyAddresses` deixa de existir na nuvem.

| Regra | Severidade | O que verifica | Como corrigir |
|---|---|---|---|
| `PRX-001` | Aviso | `proxyAddresses` vazio em objeto com `mail` preenchido | Incluir `SMTP:<mail>` e todos os aliases que o objeto já tem na nuvem, para que não sejam perdidos. |
| `PRX-002` | Erro | Nenhum endereço marcado como primário (`SMTP:`) | Marcar o endereço principal com `SMTP:` em maiúsculo. |
| `PRX-003` | Erro | Mais de um endereço primário | Manter apenas um `SMTP:` em maiúsculo e deixar os demais em minúsculo. |
| `PRX-004` | Aviso | Primário diferente do atributo `mail` | Alinhar os dois. |
| `PRX-005` | Erro | Endereço com espaço ou caractere inválido | Corrigir ou remover o endereço. |
| `PRX-006` | Aviso | Endereço com domínio não roteável (ex.: `@empresa.local`) | Remover. Ele será descartado na nuvem de qualquer forma. |
| `PRX-007` | Aviso | O mesmo endereço repetido no próprio objeto | Remover a entrada repetida. |

> Sem o esquema do Exchange estendido, `proxyAddresses` ainda existe no AD e é editado pela aba *Attribute Editor* em *Active Directory Users and Computers* (com *Advanced Features* habilitado).

## Duplicidade

| Regra | Severidade | O que verifica | Como corrigir |
|---|---|---|---|
| `DUP-001` | Erro | O mesmo endereço (UPN, `mail` ou `proxyAddresses`) aparece em mais de um objeto do domínio | Manter o endereço em apenas um objeto. Esse é o erro `AttributeValueMustBeUnique` do Entra Connect, e o objeto em conflito fica sem sincronizar. |

O relatório informa o DN dos outros objetos que usam o mesmo endereço. A verificação inclui usuários desabilitados, grupos e contatos, porque todos podem conflitar na nuvem.

## Outros atributos

| Regra | Severidade | O que verifica | Como corrigir |
|---|---|---|---|
| `SAM-001` | Erro | `sAMAccountName` com caracteres inválidos (`" / \ [ ] : ; \| = , + * ? < > @`) | Renomear a conta. |
| `SAM-002` | Aviso | `sAMAccountName` com mais de 20 caracteres | Encurtar. Nomes longos causam problemas com aplicações legadas e com o login no formato `DOMINIO\usuario`. |
| `DSP-001` | Aviso | `displayName` vazio | Preencher. Sem ele, o nome exibido no Microsoft 365 fica inconsistente. |
| `DSP-002` | Erro | `displayName` com mais de 256 caracteres | Encurtar. |
| `NAM-001` | Erro | `givenName` ou `sn` com mais de 64 caracteres | Encurtar. |
| `NCK-001` | Erro | `mailNickname` com espaço, `@` ou caractere inválido | Ajustar. Avaliado apenas se o esquema do Exchange estiver estendido. |
| `NCK-002` | Erro | `mailNickname` com mais de 64 caracteres | Encurtar. |
| `WSP-001` | Aviso | Espaço sobrando no início ou no fim de um valor | Remover os espaços. |

## Execução

| Regra | Severidade | O que verifica | Como corrigir |
|---|---|---|---|
| `EXE-001` | Aviso | Uma exceção ocorreu ao avaliar o objeto | Verificar o objeto manualmente. Se o problema se repetir, abra uma issue com a mensagem de erro, sem dados reais. |

---

## Objetos ignorados

Os mesmos objetos que o Entra Connect não sincroniza por padrão ficam fora da avaliação: objetos críticos do sistema (`isCriticalSystemObject`), como `krbtgt`, `Guest`/`Convidado` e grupos administrativos internos, e contas de serviço com os prefixos `MSOL_`, `AAD_`, `Sync_`, `HealthMailbox`, `SystemMailbox`, `FederatedEmail`, `DiscoverySearchMailbox`, `Migration.`, `SUPPORT_388945a0` e `CAS_`.

A quantidade de contas ignoradas aparece na seção *Ambiente* do relatório.
