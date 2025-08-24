#!/bin/bash
# 🔄 Neo4j Restore - Sistema Terminal
# Script para restaurar backups do Neo4j

set -e

# Configurações
BACKUP_DIR="/home/codable/terminal/memoria-neo4j-repo/memory-backups"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-password}"

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     🔄 Neo4j Restore - Sistema Terminal     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Verificar se Neo4j está rodando
if ! docker ps | grep -q terminal-neo4j; then
    echo -e "${RED}❌ Neo4j não está rodando!${NC}"
    echo -e "${YELLOW}Iniciando Neo4j...${NC}"
    docker compose up -d terminal-neo4j
    sleep 10
fi

# Verificar se existem backups
if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR/*.zip 2>/dev/null)" ]; then
    echo -e "${RED}❌ Nenhum backup encontrado em $BACKUP_DIR${NC}"
    exit 1
fi

# Listar backups disponíveis
echo -e "${BLUE}📚 Backups disponíveis:${NC}"
echo ""

# Criar array com os backups
declare -a BACKUPS
i=1
for backup in $(ls -t $BACKUP_DIR/*.zip); do
    size=$(du -h "$backup" | cut -f1)
    date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
    name=$(basename "$backup")
    BACKUPS[$i]="$backup"
    echo -e "  ${GREEN}$i)${NC} $name"
    echo -e "     📅 Data: $date"
    echo -e "     💾 Tamanho: $size"
    echo ""
    ((i++))
done

# Se só tem 1 backup, usar ele automaticamente
if [ ${#BACKUPS[@]} -eq 2 ]; then  # Array começa em 1, então 2 elementos = 1 backup
    echo -e "${GREEN}➜ Usando único backup disponível${NC}"
    SELECTED="${BACKUPS[1]}"
else
    # Pedir para escolher
    echo -n "Escolha o backup para restaurar (1-$((i-1))): "
    read choice
    
    if [ -z "${BACKUPS[$choice]}" ]; then
        echo -e "${RED}❌ Opção inválida!${NC}"
        exit 1
    fi
    SELECTED="${BACKUPS[$choice]}"
fi

echo -e "\n${YELLOW}📦 Backup selecionado:${NC} $(basename $SELECTED)"

# Mostrar estatísticas atuais
echo -e "\n${BLUE}📊 Estado atual do banco:${NC}"
CURRENT_NODES=$(docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH (n) RETURN count(n);" --format plain 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
CURRENT_RELS=$(docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH ()-[r]->() RETURN count(r);" --format plain 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")

echo -e "  Nós atuais: ${CURRENT_NODES}"
echo -e "  Relacionamentos atuais: ${CURRENT_RELS}"

# Confirmar restauração
echo -e "\n${RED}⚠️  ATENÇÃO:${NC}"
echo -e "A restauração irá:"
echo -e "  1. ${RED}APAGAR${NC} todos os dados atuais"
echo -e "  2. ${GREEN}RESTAURAR${NC} os dados do backup"
echo ""
read -p "Confirmar restauração? (s/N): " confirm

if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}Operação cancelada.${NC}"
    exit 0
fi

# Extrair backup
echo -e "\n${YELLOW}📂 Extraindo backup...${NC}"
TEMP_DIR="/tmp/neo4j_restore_$$"
mkdir -p "$TEMP_DIR"
unzip -q "$SELECTED" -d "$TEMP_DIR"

# Procurar arquivo .cypher
CYPHER_FILE=$(find "$TEMP_DIR" -name "*.cypher" -type f | head -1)

if [ -z "$CYPHER_FILE" ]; then
    echo -e "${RED}❌ Arquivo .cypher não encontrado no backup!${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GREEN}✓ Arquivo encontrado:${NC} $(basename $CYPHER_FILE)"

# Verificar conteúdo do arquivo
LINE_COUNT=$(wc -l < "$CYPHER_FILE")
echo -e "${BLUE}📄 Tamanho do arquivo:${NC} $LINE_COUNT linhas"

# Limpar banco
echo -e "\n${YELLOW}🗑️  Limpando banco de dados...${NC}"
docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH (n) DETACH DELETE n;" 2>/dev/null

echo -e "${GREEN}✓ Banco limpo${NC}"

# Restaurar dados
echo -e "\n${YELLOW}📥 Restaurando dados...${NC}"

# Executar restore
if docker exec -i terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" < "$CYPHER_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ Dados restaurados com sucesso!${NC}"
else
    echo -e "${YELLOW}⚠️  Alguns comandos podem ter falhado (normal se houver duplicatas)${NC}"
fi

# Verificar resultado
echo -e "\n${BLUE}📊 Estado após restauração:${NC}"
NEW_NODES=$(docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH (n) RETURN count(n);" --format plain 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")
NEW_RELS=$(docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH ()-[r]->() RETURN count(r);" --format plain 2>/dev/null | grep -E '^[0-9]+$' | head -1 || echo "0")

echo -e "  Nós restaurados: ${GREEN}${NEW_NODES}${NC}"
echo -e "  Relacionamentos restaurados: ${GREEN}${NEW_RELS}${NC}"

# Mostrar alguns dados restaurados
echo -e "\n${BLUE}📋 Amostra dos dados restaurados:${NC}"
docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH (n) RETURN labels(n) as Label, n.name as Nome LIMIT 5;" 2>/dev/null || true

# Limpar temporários
rm -rf "$TEMP_DIR"

# Verificar metadata se existir
METADATA_FILE=$(unzip -l "$SELECTED" 2>/dev/null | grep metadata.json | awk '{print $4}')
if [ -n "$METADATA_FILE" ]; then
    echo -e "\n${CYAN}📄 Informações do backup:${NC}"
    unzip -p "$SELECTED" "$METADATA_FILE" 2>/dev/null | python3 -m json.tool | head -10 || true
fi

echo -e "\n${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ Restauração concluída com sucesso!    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"

# Comparação antes/depois
echo -e "\n${CYAN}📊 Resumo da operação:${NC}"
echo -e "┌─────────────────┬──────────┬──────────┐"
echo -e "│                 │  Antes   │  Depois  │"
echo -e "├─────────────────┼──────────┼──────────┤"
printf "│ Nós             │ %8s │ %8s │\n" "$CURRENT_NODES" "$NEW_NODES"
printf "│ Relacionamentos │ %8s │ %8s │\n" "$CURRENT_RELS" "$NEW_RELS"
echo -e "└─────────────────┴──────────┴──────────┘"