# SyncCheck: contexto do projeto

Módulo PowerShell **somente leitura** que avalia a prontidão do Active Directory para sincronização com o Microsoft Entra ID (Entra Connect Sync / Cloud Sync). É uma alternativa às verificações do IdFix. Projeto pessoal e de estudos de Wilson Neves de Almeida Junior, com licença MIT e sem fins comerciais.

## Estrutura

- `src/SyncCheck/SyncCheck.psm1`: todo o código, na função `Invoke-SyncCheck`.
- `src/SyncCheck/SyncCheck.psd1`: manifesto. `ModuleVersion` é a fonte única da versão.
- `docs/REGRAS.md`: catálogo das regras. Precisa ser atualizado junto com o código.
- `docs/PERMISSOES.md`, `README.md`, `CHANGELOG.md`.

## Regras obrigatórias

1. **Nunca adicionar operações de escrita no AD.** Só cmdlets `Get-AD*`. A ferramenta é somente leitura por definição, e o README e o PERMISSOES.md prometem isso.
2. **`SyncCheck.psm1` deve ser 100% ASCII.** Textos acentuados são escritos como entidade HTML (`&#231;`) e passam pela função `D` antes de ir para o console ou o CSV. O HTML do relatório pode usar as entidades diretamente. Validar com: `Select-String -Path .\src\SyncCheck\SyncCheck.psm1 -Pattern '[^\x00-\x7F]'`, que não deve retornar nada.
3. **Compatibilidade com Windows PowerShell 5.1.** Nada de sintaxe exclusiva do PS 7 (`??`, `?.`, operador ternário, `ForEach-Object -Parallel`).
4. **IDs de regra são estáveis** (`UPN-002`, `DUP-001`…). Nunca renumerar. Regras novas recebem o próximo número do prefixo.
5. **Atributos opcionais** (como `mailNickname`) só são consultados se existirem no esquema. Seguir o padrão `Test-SchemaAttr`.
6. **Nada específico de cliente** no código: domínio, sufixos e nome são detectados automaticamente.
7. Nos textos do relatório, usar "itens avaliados" e "pontos de melhoria". Não usar "achados".

## Versionamento e publicação

- SemVer: correção → patch, regra ou parâmetro novo → minor, quebra de uso → major.
- A cada versão: atualizar `ModuleVersion` no `.psd1`, o `CHANGELOG.md` e, se mudar regra, o `docs/REGRAS.md`.
- A publicação na PowerShell Gallery acontece pelo workflow `.github/workflows/publish.yml` ao criar uma release `vX.Y.Z` no GitHub (precisa do secret `PSGALLERY_API_KEY`). A tag deve bater com o `ModuleVersion`.

## Roadmap

- v1.4: parâmetro `-Language en` e relatório em inglês.
- v2.0: executável em C# (`System.DirectoryServices`), sem dependência do RSAT.
- v2.x: comparação com o Exchange Online / Entra ID (previsão de soft match e aliases que só existem na nuvem).
