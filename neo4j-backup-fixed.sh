#!/bin/bash
# 🧠 Neo4j Backup - Versão Corrigida para Capturar TODOS os Nós
# Exporta nós e relacionamentos usando ID único ao invés de apenas name

set -e

# Configurações
BACKUP_DIR="/home/codable/terminal/memoria-neo4j-repo/memory-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NEO4J_PASSWORD="${NEO4J_PASSWORD:-password}"

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      🧠 Neo4j Backup System v4.0 FIXED      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}\n"

# Verificar Neo4j
if ! docker ps | grep -q terminal-neo4j; then
    echo -e "${RED}❌ Neo4j não está rodando!${NC}"
    exit 1
fi

# Criar diretório
mkdir -p "${BACKUP_DIR}"

# Arquivos temporários
TEMP_FILE="/tmp/neo4j_backup_${TIMESTAMP}.cypher"
ZIP_FILE="${BACKUP_DIR}/BACKUP_FIXED_${TIMESTAMP}.zip"

echo -e "${YELLOW}📊 Coletando estatísticas...${NC}"

# Contar nós e relacionamentos
NODE_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1)

REL_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH ()-[r]->() RETURN count(r) as c;" --format plain 2>/dev/null | tail -1)

NODES_WITH_NAME=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) WHERE n.name IS NOT NULL RETURN count(n) as c;" --format plain 2>/dev/null | tail -1)

NODES_WITHOUT_NAME=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) WHERE n.name IS NULL RETURN count(n) as c;" --format plain 2>/dev/null | tail -1)

echo -e "  Total de Nós: ${NODE_COUNT}"
echo -e "  - Com 'name': ${NODES_WITH_NAME}"
echo -e "  - Sem 'name': ${NODES_WITHOUT_NAME}"
echo -e "  Relacionamentos: ${REL_COUNT}"

# Header do backup
cat > "$TEMP_FILE" << EOF
// ================================================
// 🧠 Neo4j Memory Backup - Terminal System
// ================================================
// Data: $(date)
// Total de Nós: ${NODE_COUNT}
// - Nós com 'name': ${NODES_WITH_NAME}
// - Nós sem 'name': ${NODES_WITHOUT_NAME}
// Relacionamentos: ${REL_COUNT}
// ================================================
// Para restaurar:
// 1. docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH (n) DETACH DELETE n;"
// 2. docker exec -i terminal-neo4j cypher-shell -u neo4j -p password < backup.cypher
// ================================================

EOF

echo -e "${YELLOW}📝 Exportando TODOS os nós (incluindo sem 'name')...${NC}"

# EXPORTAR NÓS - Capturando TODOS, incluindo sem name
echo "// ========== CRIANDO NÓS ==========" >> "$TEMP_FILE"

# Exportar nós com todas as propriedades usando apoc.export.json
docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) 
     WITH n, labels(n) as lbls, properties(n) as props, id(n) as nodeId
     RETURN lbls, props, nodeId;" --format plain 2>/dev/null | while IFS= read -r line; do
    
    # Pular header
    if [[ "$line" == "lbls, props, nodeId" ]] || [[ -z "$line" ]]; then
        continue
    fi
    
    # Processar linha com dados do nó
    if [[ "$line" =~ ^\[(.+)\],\ (\{.*\}),\ ([0-9]+)$ ]]; then
        labels="${BASH_REMATCH[1]}"
        props="${BASH_REMATCH[2]}"
        node_id="${BASH_REMATCH[3]}"
        
        # Limpar labels - remover aspas e espaços
        labels=$(echo "$labels" | sed 's/"//g' | sed 's/, /:/g')
        
        # Adicionar propriedade temporária _backup_id para rastrear nós durante restauração
        if [[ "$props" == "{}" ]]; then
            props="{_backup_id: ${node_id}}"
        else
            # Adicionar _backup_id às propriedades existentes
            props="${props%\}}, _backup_id: ${node_id}}"
        fi
        
        # Criar comando CREATE
        echo "CREATE (:${labels} ${props});" >> "$TEMP_FILE"
    fi
done

echo "" >> "$TEMP_FILE"
echo -e "${YELLOW}📝 Exportando TODOS os relacionamentos...${NC}"

# EXPORTAR RELACIONAMENTOS - Usando ID temporário para mapear
echo "// ========== CRIANDO RELACIONAMENTOS ==========" >> "$TEMP_FILE"

# Exportar relacionamentos usando IDs temporários
docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (a)-[r]->(b) 
     WITH id(a) as fromId, id(b) as toId, type(r) as relType, properties(r) as props
     RETURN fromId, toId, relType, props;" \
    --format plain 2>/dev/null | while IFS= read -r line; do
    
    # Pular header
    if [[ "$line" == "fromId, toId, relType, props" ]] || [[ -z "$line" ]]; then
        continue
    fi
    
    # Processar linha com relacionamento
    if [[ "$line" =~ ^([0-9]+),\ ([0-9]+),\ \"(.+)\",\ (\{.*\})$ ]]; then
        from_id="${BASH_REMATCH[1]}"
        to_id="${BASH_REMATCH[2]}"
        rel_type="${BASH_REMATCH[3]}"
        props="${BASH_REMATCH[4]}"
        
        # Criar comando MATCH usando _backup_id
        if [[ "$props" == "{}" ]]; then
            echo "MATCH (a {_backup_id: ${from_id}}), (b {_backup_id: ${to_id}}) CREATE (a)-[:${rel_type}]->(b);" >> "$TEMP_FILE"
        else
            echo "MATCH (a {_backup_id: ${from_id}}), (b {_backup_id: ${to_id}}) CREATE (a)-[:${rel_type} ${props}]->(b);" >> "$TEMP_FILE"
        fi
    fi
done

# Adicionar comando para limpar propriedades temporárias _backup_id
echo "" >> "$TEMP_FILE"
echo "// ========== LIMPANDO PROPRIEDADES TEMPORÁRIAS ==========" >> "$TEMP_FILE"
echo "MATCH (n) WHERE n._backup_id IS NOT NULL REMOVE n._backup_id;" >> "$TEMP_FILE"

echo "" >> "$TEMP_FILE"
echo "// ========== FIM DO BACKUP ==========" >> "$TEMP_FILE"

# Verificar quantas linhas foram exportadas
LINES_CREATE=$(grep -c "^CREATE" "$TEMP_FILE" || echo "0")
LINES_MATCH=$(grep -c "^MATCH" "$TEMP_FILE" || echo "0")

echo -e "${GREEN}✓ Comandos CREATE gerados: ${LINES_CREATE}${NC}"
echo -e "${GREEN}✓ Comandos MATCH gerados: ${LINES_MATCH}${NC}"

# Criar metadata
METADATA_FILE="/tmp/metadata_${TIMESTAMP}.json"
cat > "$METADATA_FILE" << EOF
{
    "timestamp": "${TIMESTAMP}",
    "date": "$(date)",
    "total_nodes": ${NODE_COUNT},
    "nodes_with_name": ${NODES_WITH_NAME},
    "nodes_without_name": ${NODES_WITHOUT_NAME},
    "relationships": ${REL_COUNT},
    "create_commands": ${LINES_CREATE},
    "match_commands": ${LINES_MATCH},
    "backup_version": "4.0-fixed"
}
EOF

# Criar README
README_FILE="/tmp/README_${TIMESTAMP}.txt"
cat > "$README_FILE" << EOF
Neo4j Backup - Terminal System v4.0 FIXED
==========================================
Data: $(date)
Total de Nós: ${NODE_COUNT}
- Com 'name': ${NODES_WITH_NAME}
- Sem 'name': ${NODES_WITHOUT_NAME}
Relacionamentos: ${REL_COUNT}
Comandos CREATE: ${LINES_CREATE}
Comandos MATCH: ${LINES_MATCH}

IMPORTANTE: Esta versão captura TODOS os nós,
incluindo aqueles sem a propriedade 'name'.

Para restaurar:
1. unzip BACKUP_FIXED_${TIMESTAMP}.zip
2. docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH (n) DETACH DELETE n;"
3. docker exec -i terminal-neo4j cypher-shell -u neo4j -p password < neo4j_backup_${TIMESTAMP}.cypher
EOF

echo -e "${YELLOW}📦 Criando arquivo ZIP...${NC}"

# Criar ZIP
cd /tmp
zip -q "$ZIP_FILE" \
    "neo4j_backup_${TIMESTAMP}.cypher" \
    "metadata_${TIMESTAMP}.json" \
    "README_${TIMESTAMP}.txt"

# Limpar temporários
rm -f "$TEMP_FILE" "$METADATA_FILE" "$README_FILE"

echo -e "\n${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    ✅ Backup COMPLETO concluído com sucesso!  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}\n"

echo -e "📦 Arquivo: ${CYAN}$(basename $ZIP_FILE)${NC}"
echo -e "📊 Total: ${NODE_COUNT} nós (${NODES_WITH_NAME} com name, ${NODES_WITHOUT_NAME} sem name)"
echo -e "🔗 Relacionamentos: ${REL_COUNT}"
echo -e "💾 Tamanho: $(du -h "$ZIP_FILE" | cut -f1)"

# Verificar qualidade do backup
if [[ "${LINES_CREATE}" -lt "${NODE_COUNT}" ]]; then
    echo -e "\n${RED}⚠️ AVISO: Apenas ${LINES_CREATE} de ${NODE_COUNT} nós foram exportados!${NC}"
    echo -e "${YELLOW}Verifique o log de execução para possíveis erros.${NC}"
else
    echo -e "\n${GREEN}✅ Backup validado: TODOS os ${NODE_COUNT} nós foram exportados!${NC}"
fi

echo -e "\n${CYAN}📚 Últimos 3 backups:${NC}"
ls -lht "${BACKUP_DIR}"/*.zip 2>/dev/null | head -3