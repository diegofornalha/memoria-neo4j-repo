#!/bin/bash
# 🧠 Neo4j Backup - Versão Final Funcional
# Exporta nós e relacionamentos corretamente

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
echo -e "${CYAN}║      🧠 Neo4j Backup System v3.0 Final      ║${NC}"
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
ZIP_FILE="${BACKUP_DIR}/BACKUP_${TIMESTAMP}.zip"

echo -e "${YELLOW}📊 Coletando estatísticas...${NC}"

# Contar nós e relacionamentos
NODE_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1)

REL_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH ()-[r]->() RETURN count(r) as c;" --format plain 2>/dev/null | tail -1)

echo -e "  Nós: ${NODE_COUNT}"
echo -e "  Relacionamentos: ${REL_COUNT}"

# Header do backup
cat > "$TEMP_FILE" << EOF
// ================================================
// 🧠 Neo4j Memory Backup - Terminal System
// ================================================
// Data: $(date)
// Nós: ${NODE_COUNT}
// Relacionamentos: ${REL_COUNT}
// ================================================
// Para restaurar:
// 1. docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH (n) DETACH DELETE n;"
// 2. docker exec -i terminal-neo4j cypher-shell -u neo4j -p password < backup.cypher
// ================================================

EOF

echo -e "${YELLOW}📝 Exportando nós...${NC}"

# EXPORTAR NÓS - Processando a saída real do Neo4j
echo "// ========== CRIANDO NÓS ==========" >> "$TEMP_FILE"

# Obter todos os nós e processar linha por linha
docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) RETURN n;" --format plain 2>/dev/null | while IFS= read -r line; do
    
    # Pular header
    if [[ "$line" == "n" ]] || [[ -z "$line" ]]; then
        continue
    fi
    
    # Processar linha que contém um nó
    if [[ "$line" =~ ^\(: ]]; then
        # Remover parênteses externos
        node_data="${line#(}"
        node_data="${node_data%)}"
        
        # Extrair labels (tudo antes do primeiro {)
        labels="${node_data%%\{*}"
        labels="${labels#:}"  # Remover : inicial
        
        # Extrair propriedades (tudo entre { })
        props="${node_data#*\{}"
        props="{${props}"
        
        # Criar comando CREATE
        echo "CREATE (:${labels} ${props});" >> "$TEMP_FILE"
    fi
done

echo "" >> "$TEMP_FILE"
echo -e "${YELLOW}📝 Exportando relacionamentos...${NC}"

# EXPORTAR RELACIONAMENTOS
echo "// ========== CRIANDO RELACIONAMENTOS ==========" >> "$TEMP_FILE"

# Exportar relacionamentos usando o formato correto
docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (a)-[r]->(b) WHERE a.name IS NOT NULL AND b.name IS NOT NULL RETURN a.name as from_name, type(r) as rel_type, b.name as to_name, properties(r) as props;" \
    --format plain 2>/dev/null | while IFS= read -r line; do
    
    # Pular header
    if [[ "$line" == "from_name, rel_type, to_name, props" ]] || [[ -z "$line" ]]; then
        continue
    fi
    
    # Processar linha com relacionamento
    # Formato: "nome1", "TIPO", "nome2", {propriedades}
    if [[ "$line" =~ \"(.+)\",\ \"(.+)\",\ \"(.+)\",\ (\{.*\}) ]]; then
        from_name="${BASH_REMATCH[1]}"
        rel_type="${BASH_REMATCH[2]}"
        to_name="${BASH_REMATCH[3]}"
        props="${BASH_REMATCH[4]}"
        
        # Se não há propriedades, props será {}
        if [[ "$props" == "{}" ]]; then
            echo "MATCH (a {name: \"${from_name}\"}), (b {name: \"${to_name}\"}) CREATE (a)-[:${rel_type}]->(b);" >> "$TEMP_FILE"
        else
            # Formatar propriedades
            props_formatted=$(echo "$props" | sed 's/: "/: "/g')
            echo "MATCH (a {name: \"${from_name}\"}), (b {name: \"${to_name}\"}) CREATE (a)-[:${rel_type} ${props_formatted}]->(b);" >> "$TEMP_FILE"
        fi
    fi
done

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
    "nodes": ${NODE_COUNT},
    "relationships": ${REL_COUNT},
    "create_commands": ${LINES_CREATE},
    "match_commands": ${LINES_MATCH},
    "backup_version": "3.0-final"
}
EOF

# Criar README
README_FILE="/tmp/README_${TIMESTAMP}.txt"
cat > "$README_FILE" << EOF
Neo4j Backup - Terminal System v3.0
====================================
Data: $(date)
Nós: ${NODE_COUNT}
Relacionamentos: ${REL_COUNT}
Comandos CREATE: ${LINES_CREATE}
Comandos MATCH: ${LINES_MATCH}

Para restaurar:
1. unzip BACKUP_${TIMESTAMP}.zip
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

# Limpar arquivos antigos não-ZIP
find "${BACKUP_DIR}" -type f ! -name "*.zip" -delete 2>/dev/null || true

echo -e "\n${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       ✅ Backup concluído com sucesso!       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}\n"

echo -e "📦 Arquivo: ${CYAN}$(basename $ZIP_FILE)${NC}"
echo -e "📊 Total: ${NODE_COUNT} nós, ${REL_COUNT} relacionamentos"
echo -e "💾 Tamanho: $(du -h "$ZIP_FILE" | cut -f1)"

# Verificar se o backup tem conteúdo
if [[ "${LINES_CREATE}" == "0" ]]; then
    echo -e "\n${RED}⚠️ AVISO: Nenhum comando CREATE foi gerado!${NC}"
    echo -e "${YELLOW}Verifique se o Neo4j tem dados.${NC}"
fi

echo -e "\n${CYAN}📚 Últimos 3 backups:${NC}"
ls -lht "${BACKUP_DIR}"/*.zip 2>/dev/null | head -3