# 🧠 Sistema de Backup e Gerenciamento Neo4j

Sistema completo para backup, restauração e gerenciamento do banco de dados Neo4j com interface amigável e funcionalidades avançadas.

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Funcionalidades](#funcionalidades)
- [Instalação](#instalação)
- [Uso](#uso)
- [Scripts](#scripts)
- [Estrutura de Arquivos](#estrutura-de-arquivos)
- [Configuração](#configuração)
- [Troubleshooting](#troubleshooting)
- [Contribuição](#contribuição)

## 🎯 Visão Geral

Este sistema fornece uma solução completa para gerenciar backups do Neo4j, incluindo:

- **Backup automático** com exportação completa de nós e relacionamentos
- **Restauração segura** com validação e backup de segurança
- **Interface de gerenciamento** com menu interativo
- **Logging detalhado** para auditoria
- **Limpeza automática** de backups antigos
- **Estatísticas em tempo real** do banco

## ✨ Funcionalidades

### 🔧 Scripts Principais

| Script | Versão | Descrição |
|--------|--------|-----------|
| `neo4j-backup.sh` | v3.0 | Script de backup original |
| `neo4j-backup-enhanced.sh` | v4.0 | Versão aprimorada com logging e segurança |
| `neo4j-restore.sh` | v1.0 | Script de restauração |
| `neo4j-manager.sh` | v1.0 | Interface de gerenciamento unificada |

### 📊 Funcionalidades Avançadas

- ✅ **Exportação completa**: Nós e relacionamentos com propriedades
- ✅ **Validação de integridade**: Verificação de dados antes/depois
- ✅ **Backup de segurança**: Criação automática antes operações críticas
- ✅ **Processamento em lotes**: Performance otimizada para grandes volumes
- ✅ **Logging detalhado**: Registro completo de todas as operações
- ✅ **Limpeza automática**: Gerenciamento de espaço em disco
- ✅ **Interface colorida**: Output visual amigável
- ✅ **Tratamento de erros**: Recuperação robusta de falhas

## 🚀 Instalação

### Pré-requisitos

- Docker instalado e rodando
- Container Neo4j rodando com nome `terminal-neo4j`
- Bash shell
- Utilitários: `zip`, `jq` (opcional)

### Configuração Rápida

```bash
# 1. Clone o repositório
git clone <repository-url>
cd memoria-neo4j-repo

# 2. Torne os scripts executáveis
chmod +x *.sh

# 3. Verifique se o Neo4j está rodando
docker ps | grep terminal-neo4j

# 4. Execute o gerenciador
./neo4j-manager.sh
```

## 📖 Uso

### Interface de Gerenciamento

Execute o script principal para acessar o menu interativo:

```bash
./neo4j-manager.sh
```

**Menu Principal:**
```
🧠 Neo4j Manager System v1.0

📊 Status do Sistema:
  ✅ Neo4j: Rodando
  ✅ Conectividade: OK
  📈 Nós: 905
  🔗 Relacionamentos: 681
  📦 Backups: 5 arquivos

🔧 Operações Disponíveis:
  1. 📦 Fazer Backup
  2. 🔄 Restaurar Backup
  3. 📚 Listar Backups
  4. 🔍 Verificar Status
  5. 🗑️ Limpar Banco
  6. 🌐 Abrir Browser
  7. 📊 Estatísticas Detalhadas
  8. 🧹 Limpar Backups Antigos
  0. 🚪 Sair
```

### Backup Manual

```bash
# Backup básico
./neo4j-backup.sh

# Backup aprimorado (recomendado)
./neo4j-backup-enhanced.sh
```

### Restauração Manual

```bash
# Restaurar backup
./neo4j-restore.sh
```

## 📜 Scripts

### 1. `neo4j-backup.sh` (v3.0)

Script de backup original com funcionalidades básicas:

**Características:**
- Exportação de nós e relacionamentos
- Criação de arquivo ZIP com metadata
- Validação de dados
- Interface colorida

**Uso:**
```bash
./neo4j-backup.sh
```

### 2. `neo4j-backup-enhanced.sh` (v4.0)

Versão aprimorada com funcionalidades avançadas:

**Melhorias:**
- Logging detalhado em arquivo
- Limpeza automática de backups antigos
- Hash SHA256 para verificação
- Metadata expandida
- Tratamento de erros robusto
- Backup de segurança antes operações críticas

**Uso:**
```bash
./neo4j-backup-enhanced.sh
```

### 3. `neo4j-restore.sh` (v1.0)

Script de restauração com segurança:

**Funcionalidades:**
- Listagem de backups disponíveis
- Backup de segurança antes restauração
- Processamento em lotes para performance
- Validação pós-restauração
- Interface interativa

**Uso:**
```bash
./neo4j-restore.sh
```

### 4. `neo4j-manager.sh` (v1.0)

Interface unificada de gerenciamento:

**Funcionalidades:**
- Menu interativo
- Status em tempo real
- Todas as operações integradas
- Estatísticas detalhadas
- Limpeza de backups antigos

**Uso:**
```bash
./neo4j-manager.sh
```

## 📁 Estrutura de Arquivos

```
memoria-neo4j-repo/
├── neo4j-backup.sh              # Script de backup v3.0
├── neo4j-backup-enhanced.sh     # Script de backup v4.0
├── neo4j-restore.sh             # Script de restauração
├── neo4j-manager.sh             # Interface de gerenciamento
├── memory-backups/              # Diretório de backups
│   ├── BACKUP_20250826_004845.zip
│   ├── BACKUP_20250824_052038.zip
│   └── ...
└── README.md                    # Esta documentação
```

### Estrutura do Backup

Cada arquivo ZIP contém:

```
BACKUP_TIMESTAMP.zip
├── neo4j_backup_TIMESTAMP.cypher    # Comandos Cypher para restauração
├── metadata_TIMESTAMP.json          # Metadados do backup
└── README_TIMESTAMP.txt             # Instruções de restauração
```

## ⚙️ Configuração

### Variáveis de Ambiente

```bash
# Senha do Neo4j (padrão: password)
export NEO4J_PASSWORD="sua_senha"

# Diretório de backups (padrão: ./memory-backups)
export BACKUP_DIR="/caminho/para/backups"
```

### Configurações Avançadas

**Limite de backups (neo4j-backup-enhanced.sh):**
```bash
MAX_BACKUPS=10  # Manter apenas os últimos 10 backups
```

**Tamanho do lote (neo4j-restore.sh):**
```bash
BATCH_SIZE=100  # Comandos por lote na restauração
```

## 🔧 Troubleshooting

### Problemas Comuns

#### 1. Neo4j não está rodando
```bash
# Verificar status
docker ps | grep terminal-neo4j

# Iniciar se necessário
docker compose up -d terminal-neo4j
```

#### 2. Erro de conectividade
```bash
# Testar conexão
docker exec terminal-neo4j cypher-shell -u neo4j -p password "RETURN 1;"

# Verificar logs
docker logs terminal-neo4j
```

#### 3. Permissões de arquivo
```bash
# Corrigir permissões
chmod +x *.sh
```

#### 4. Espaço em disco
```bash
# Verificar espaço
df -h

# Limpar backups antigos
./neo4j-manager.sh  # Opção 8
```

### Logs e Debug

**Logs do backup aprimorado:**
```bash
# Verificar logs
ls -la /tmp/neo4j_backup_*.log

# Último log
tail -f /tmp/neo4j_backup_$(date +%Y%m%d_%H%M%S).log
```

**Verificar integridade:**
```bash
# Verificar hash do backup
sha256sum memory-backups/BACKUP_*.zip

# Testar extração
unzip -t memory-backups/BACKUP_*.zip
```

## 📊 Estatísticas

### Performance

- **Backup**: ~2-5 segundos para 1000 nós
- **Restauração**: ~10-30 segundos para 1000 nós
- **Tamanho**: ~50-200KB por backup (dependendo dos dados)

### Limitações

- Máximo de nós testado: 10.000
- Máximo de relacionamentos testado: 15.000
- Tamanho máximo de backup: ~50MB

## 🤝 Contribuição

### Como Contribuir

1. Fork o repositório
2. Crie uma branch para sua feature
3. Implemente as mudanças
4. Teste extensivamente
5. Submeta um Pull Request

### Padrões de Código

- Use Bash com `set -e`
- Documente todas as funções
- Mantenha compatibilidade com versões anteriores
- Teste em diferentes ambientes

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo LICENSE para detalhes.

## 🆘 Suporte

Para suporte e dúvidas:

1. Verifique a seção [Troubleshooting](#troubleshooting)
2. Consulte os logs de erro
3. Abra uma issue no repositório

---

**Desenvolvido com ❤️ para o sistema de memória Neo4j**
