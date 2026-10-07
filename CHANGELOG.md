# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). Versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [1.3.0] - 2026-10-07

Primeira versão pública.

### Adicionado
- Distribuição como módulo PowerShell (`Invoke-SyncCheck`), publicado na PowerShell Gallery.
- Parâmetro `-PassThru` para usar os itens avaliados no pipeline.
- Ajuda completa via `Get-Help Invoke-SyncCheck -Full`.
- Documentação: pré-requisitos, permissões e catálogo de regras.

### Alterado
- A versão exibida no relatório passa a ser lida do manifesto do módulo.

## [1.2.0] - 2026-10-07

### Corrigido
- Falha em ambientes sem o esquema do Exchange estendido (`mailNickname` inexistente). Os atributos opcionais agora são detectados no esquema antes da consulta.
- Nome do cliente aparecia em branco no início da execução.

### Adicionado
- Situação do esquema do Exchange na seção Ambiente do relatório.

## [1.1.0] - 2026-10-07

### Alterado
- Detecção automática de cliente (NetBIOS) e sufixos UPN roteáveis. Nada fixo de ambiente específico.
- Código 100% ASCII: funciona em qualquer codificação do Windows PowerShell 5.1.

### Adicionado
- Parâmetros `-Server` e `-Credential`.
- Falhas ao avaliar um objeto não interrompem a execução (regra `EXE-001`).
- Mensagem orientando a instalação do RSAT quando o módulo ActiveDirectory não existe.

## [1.0.0] - 2026-10-06

### Adicionado
- Versão inicial: 24 regras para UPN, mail, proxyAddresses, duplicidade e limites de atributos, com relatório CSV e HTML.
