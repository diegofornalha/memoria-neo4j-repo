#!/bin/bash
# 🧠 Neo4j Restore - Script de Restauração
# Restaura backups do Neo4j de forma segura

set -e

# Configurações
BACKUP_DIR="/home/codable/terminal/memoria-neo4j-repo/memory-backups"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-password}"

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      🧠 Neo4j Restore System v1.0          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}\n"

# Verificar Neo4j
echo -e "${YELLOW}🔍 Verificando Neo4j...${NC}"
if ! docker ps | grep -q terminal-neo4j; then
    echo -e "${RED}❌ Neo4j não está rodando!${NC}"
    exit 1
fi

# Verificar conectividade
if ! docker exec terminal-neo4j cypher-shell -u neo4j -p password "RETURN 1;" --format plain >/dev/null 2>&1; then
    echo -e "${RED}❌ Não foi possível conectar ao Neo4j!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Neo4j está rodando e acessível${NC}\n"

# Listar backups disponíveis
echo -e "${YELLOW}📚 Backups disponíveis:${NC}"
cd "$BACKUP_DIR"
BACKUP_FILES=($(ls -t BACKUP_*.zip 2>/dev/null))

if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
    echo -e "${RED}❌ Nenhum backup encontrado em $BACKUP_DIR${NC}"
    exit 1
fi

for i in "${!BACKUP_FILES[@]}"; do
    BACKUP_FILE="${BACKUP_FILES[$i]}"
    BACKUP_DATE=$(echo "$BACKUP_FILE" | sed 's/BACKUP_\(.*\)\.zip/\1/')
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "  ${CYAN}$((i+1)).${NC} $BACKUP_FILE (${BACKUP_SIZE}) - ${BACKUP_DATE}"
done

# Selecionar backup
echo -e "\n${YELLOW}Escolha o backup para restaurar (1-${#BACKUP_FILES[@]}):${NC}"
read -r choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#BACKUP_FILES[@]} ]]; then
    echo -e "${RED}❌ Escolha inválida!${NC}"
    exit 1
fi

SELECTED_BACKUP="${BACKUP_FILES[$((choice-1))]}"
echo -e "\n${BLUE}📦 Backup selecionado: ${CYAN}$SELECTED_BACKUP${NC}"

# Confirmar restauração
echo -e "\n${RED}⚠️ ATENÇÃO: Esta operação irá APAGAR todos os dados atuais do Neo4j!${NC}"
echo -e "${YELLOW}Deseja continuar? (s/N):${NC}"
read -r confirm

if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
    echo -e "${YELLOW}❌ Restauração cancelada.${NC}"
    exit 0
fi

# Extrair backup
echo -e "\n${YELLOW}📦 Extraindo backup...${NC}"
TEMP_DIR="/tmp/neo4j_restore_$$"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

unzip -q "$BACKUP_DIR/$SELECTED_BACKUP"

# Verificar arquivos extraídos
if [[ ! -f *.cypher ]]; then
    echo -e "${RED}❌ Arquivo Cypher não encontrado no backup!${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

CYPHER_FILE=$(ls *.cypher)
METADATA_FILE=$(ls *.json 2>/dev/null || echo "")
README_FILE=$(ls *.txt 2>/dev/null || echo "")

echo -e "${GREEN}✅ Backup extraído: $CYPHER_FILE${NC}"

# Mostrar informações do backup
if [[ -n "$METADATA_FILE" ]]; then
    echo -e "\n${BLUE}📊 Informações do backup:${NC}"
    cat "$METADATA_FILE" | jq '.' 2>/dev/null || cat "$METADATA_FILE"
fi

if [[ -n "$README_FILE" ]]; then
    echo -e "\n${BLUE}📖 Instruções:${NC}"
    cat "$README_FILE"
fi

# Backup dos dados atuais (opcional)
echo -e "\n${YELLOW}💾 Fazendo backup dos dados atuais...${NC}"
CURRENT_NODES=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1 || echo "0")

if [[ "$CURRENT_NODES" != "0" ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SAFETY_BACKUP="$BACKUP_DIR/SAFETY_BACKUP_${TIMESTAMP}.zip"
    
    # Criar backup de segurança
    docker exec terminal-neo4j cypher-shell -u neo4j -p password \
        "MATCH (n) RETURN n;" --format plain > "$TEMP_DIR/current_nodes.cypher" 2>/dev/null || true
    
    docker exec terminal-neo4j cypher-shell -u neo4j -p password \
        "MATCH (a)-[r]->(b) WHERE a.name IS NOT NULL AND b.name IS NOT NULL RETURN a.name, type(r), b.name;" \
        --format plain > "$TEMP_DIR/current_rels.cypher" 2>/dev/null || true
    
    cd "$TEMP_DIR"
    zip -q "$SAFETY_BACKUP" current_nodes.cypher current_rels.cypher 2>/dev/null || true
    
    echo -e "${GREEN}✅ Backup de segurança criado: $(basename $SAFETY_BACKUP)${NC}"
else
    echo -e "${YELLOW}ℹ️ Nenhum dado atual para fazer backup${NC}"
fi

# Limpar dados atuais
echo -e "\n${RED}🗑️ Limpando dados atuais...${NC}"
docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH (n) DETACH DELETE n;" --format plain

echo -e "${GREEN}✅ Dados atuais removidos${NC}"

# Restaurar backup
echo -e "\n${YELLOW}🔄 Restaurando backup...${NC}"
cd "$TEMP_DIR"

# Contar linhas para progresso
TOTAL_LINES=$(wc -l < "$CYPHER_FILE")
CURRENT_LINE=0

echo -e "${BLUE}📝 Executando $TOTAL_LINES comandos...${NC}"

# Executar comandos em lotes para melhor performance
BATCH_SIZE=100
BATCH_FILE="/tmp/batch_$$.cypher"

while IFS= read -r line; do
    CURRENT_LINE=$((CURRENT_LINE + 1))
    
    # Pular comentários e linhas vazias
    if [[ "$line" =~ ^[[:space:]]*// ]] || [[ -z "$line" ]]; then
        continue
    fi
    
    # Adicionar linha ao lote
    echo "$line" >> "$BATCH_FILE"
    
    # Executar lote quando atingir o tamanho ou for a última linha
    if [[ $(wc -l < "$BATCH_FILE") -ge $BATCH_SIZE ]] || [[ $CURRENT_LINE -eq $TOTAL_LINES ]]; then
        if [[ -s "$BATCH_FILE" ]]; then
            docker exec -i terminal-neo4j cypher-shell -u neo4j -p password < "$BATCH_FILE" >/dev/null 2>&1 || true
            echo -ne "\r${CYAN}Progresso: $CURRENT_LINE/$TOTAL_LINES linhas processadas${NC}"
        fi
        > "$BATCH_FILE"  # Limpar arquivo de lote
    fi
done < "$CYPHER_FILE"

echo -e "\n${GREEN}✅ Restauração concluída!${NC}"

# Verificar restauração
echo -e "\n${YELLOW}🔍 Verificando restauração...${NC}"
RESTORED_NODES=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1 || echo "0")

RESTORED_RELS=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH ()-[r]->() RETURN count(r) as c;" --format plain 2>/dev/null | tail -1 || echo "0")

echo -e "  📈 Nós restaurados: ${RESTORED_NODES}"
echo -e "  🔗 Relacionamentos restaurados: ${RESTORED_RELS}"

# Limpeza
rm -rf "$TEMP_DIR"
rm -f "$BATCH_FILE"

echo -e "\n${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       ✅ Restauração concluída!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}\n"

echo -e "📦 Backup restaurado: ${CYAN}$SELECTED_BACKUP${NC}"
echo -e "📊 Resultado: ${RESTORED_NODES} nós, ${RESTORED_RELS} relacionamentos"
echo -e "🔗 Neo4j Browser: http://localhost:7474"