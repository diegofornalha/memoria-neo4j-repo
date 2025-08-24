#!/bin/bash
# 🗑️ Neo4j Clean - Limpeza do Banco de Dados
# Script para limpar completamente o Neo4j

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configurações
NEO4J_PASSWORD="${NEO4J_PASSWORD:-password}"

echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║     🗑️  Neo4j Clean - Limpeza Total         ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}\n"

# Verificar se Neo4j está rodando
if ! docker ps | grep -q terminal-neo4j; then
    echo -e "${RED}❌ Neo4j não está rodando!${NC}"
    echo -e "${YELLOW}Iniciando Neo4j...${NC}"
    docker compose up -d terminal-neo4j
    sleep 10
fi

# Mostrar estatísticas atuais
echo -e "${CYAN}📊 Estado atual do banco:${NC}"
NODES=$(docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH (n) RETURN count(n);" --format plain 2>/dev/null | tail -1)
RELS=$(docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH ()-[r]->() RETURN count(r);" --format plain 2>/dev/null | tail -1)

echo -e "  Nós: ${YELLOW}${NODES}${NC}"
echo -e "  Relacionamentos: ${YELLOW}${RELS}${NC}"

# Se banco já está vazio
if [[ "$NODES" == "0" ]] && [[ "$RELS" == "0" ]]; then
    echo -e "\n${GREEN}✅ O banco já está vazio!${NC}"
    exit 0
fi

# Mostrar preview dos dados que serão apagados
echo -e "\n${MAGENTA}📋 Preview dos dados que serão apagados:${NC}"
docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH (n) RETURN DISTINCT labels(n) as Label, count(*) as Quantidade ORDER BY Quantidade DESC LIMIT 10;" 2>/dev/null || true

echo ""

# Confirmar limpeza
echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║              ⚠️  ATENÇÃO CRÍTICA             ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}Esta operação irá:${NC}"
echo -e "  • ${RED}APAGAR PERMANENTEMENTE${NC} todos os nós"
echo -e "  • ${RED}APAGAR PERMANENTEMENTE${NC} todos os relacionamentos"
echo -e "  • ${RED}NÃO PODE SER DESFEITA${NC} sem um backup"
echo ""
echo -e "${CYAN}💡 Dica: Execute ./neo4j-backup.sh antes de limpar!${NC}"
echo ""

# Pedir confirmação dupla
read -p "$(echo -e ${YELLOW}Tem certeza que deseja limpar TODO o banco? [s/N]: ${NC})" confirm1

if [[ ! "$confirm1" =~ ^[Ss]$ ]]; then
    echo -e "${GREEN}Operação cancelada. Banco mantido intacto.${NC}"
    exit 0
fi

# Segunda confirmação
echo ""
read -p "$(echo -e ${RED}SEGUNDA CONFIRMAÇÃO - Digite 'LIMPAR' para confirmar: ${NC})" confirm2

if [[ "$confirm2" != "LIMPAR" ]]; then
    echo -e "${GREEN}Operação cancelada. Banco mantido intacto.${NC}"
    exit 0
fi

# Executar limpeza
echo -e "\n${YELLOW}🔄 Executando limpeza...${NC}"

# Limpar todos os nós e relacionamentos
docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH (n) DETACH DELETE n;" 2>/dev/null

echo -e "${GREEN}✅ Limpeza executada!${NC}"

# Verificar resultado
echo -e "\n${CYAN}📊 Estado após limpeza:${NC}"
NEW_NODES=$(docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH (n) RETURN count(n);" --format plain 2>/dev/null | tail -1)
NEW_RELS=$(docker exec terminal-neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
    "MATCH ()-[r]->() RETURN count(r);" --format plain 2>/dev/null | tail -1)

echo -e "  Nós: ${GREEN}${NEW_NODES}${NC}"
echo -e "  Relacionamentos: ${GREEN}${NEW_RELS}${NC}"

# Resumo
echo -e "\n${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✅ Banco limpo com sucesso!          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}\n"

echo -e "${CYAN}📊 Resumo da operação:${NC}"
echo -e "┌─────────────────┬──────────┬──────────┐"
echo -e "│                 │  Antes   │  Depois  │"
echo -e "├─────────────────┼──────────┼──────────┤"
printf "│ Nós             │ %8s │ %8s │\n" "$NODES" "$NEW_NODES"
printf "│ Relacionamentos │ %8s │ %8s │\n" "$RELS" "$NEW_RELS"
echo -e "└─────────────────┴──────────┴──────────┘"

echo -e "\n${CYAN}💡 Para restaurar dados:${NC}"
echo -e "   Execute: ${GREEN}./neo4j-restore.sh${NC}"