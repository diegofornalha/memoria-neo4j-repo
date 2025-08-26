#!/bin/bash
# 🧠 Neo4j Backup - Versão Aprimorada v4.0
# Exporta nós e relacionamentos com melhorias de segurança e logging

set -e

# Configurações
BACKUP_DIR="/home/codable/terminal/memoria-neo4j-repo/memory-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NEO4J_PASSWORD="${NEO4J_PASSWORD:-password}"
LOG_FILE="/tmp/neo4j_backup_${TIMESTAMP}.log"
MAX_BACKUPS=10  # Manter apenas os últimos 10 backups

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Função de logging
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Função de limpeza
cleanup() {
    log "${YELLOW}🧹 Limpando arquivos temporários...${NC}"
    rm -f /tmp/neo4j_backup_*.cypher /tmp/metadata_*.json /tmp/README_*.txt 2>/dev/null || true
    
    # Manter apenas os últimos MAX_BACKUPS
    log "${YELLOW}🗂️ Mantendo apenas os últimos ${MAX_BACKUPS} backups...${NC}"
    cd "$BACKUP_DIR"
    ls -t *.zip 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
}

# Trap para limpeza em caso de erro
trap cleanup EXIT

log "${CYAN}╔══════════════════════════════════════════════╗${NC}"
log "${CYAN}║      🧠 Neo4j Backup System v4.0 Enhanced   ║${NC}"
log "${CYAN}╚══════════════════════════════════════════════╝${NC}\n"

log "${BLUE}📅 Início: $(date)${NC}"
log "${BLUE}📝 Log: $LOG_FILE${NC}\n"

# Verificar Neo4j
log "${YELLOW}🔍 Verificando Neo4j...${NC}"
if ! docker ps | grep -q terminal-neo4j; then
    log "${RED}❌ Neo4j não está rodando!${NC}"
    exit 1
fi

# Verificar conectividade
if ! docker exec terminal-neo4j cypher-shell -u neo4j -p password "RETURN 1;" --format plain >/dev/null 2>&1; then
    log "${RED}❌ Não foi possível conectar ao Neo4j!${NC}"
    exit 1
fi

log "${GREEN}✅ Neo4j está rodando e acessível${NC}\n"

# Criar diretório
mkdir -p "${BACKUP_DIR}"

# Arquivos temporários
TEMP_FILE="/tmp/neo4j_backup_${TIMESTAMP}.cypher"
ZIP_FILE="${BACKUP_DIR}/BACKUP_${TIMESTAMP}.zip"

log "${YELLOW}📊 Coletando estatísticas...${NC}"

# Contar nós e relacionamentos com melhor tratamento de erro
NODE_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1 || echo "0")

REL_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
    "MATCH ()-[r]->() RETURN count(r) as c;" --format plain 2>/dev/null | tail -1 || echo "0")

# Verificar se os valores são numéricos
if ! [[ "$NODE_COUNT" =~ ^[0-9]+$ ]] || ! [[ "$REL_COUNT" =~ ^[0-9]+$ ]]; then
    log "${RED}❌ Erro ao obter estatísticas do Neo4j${NC}"
    exit 1
fi

log "  📈 Nós: ${NODE_COUNT}"
log "  🔗 Relacionamentos: ${REL_COUNT}"

# Verificar se há dados
if [[ "$NODE_COUNT" == "0" ]]; then
    log "${YELLOW}⚠️ Aviso: Nenhum nó encontrado no banco${NC}"
fi

# Header do backup
cat > "$TEMP_FILE" << EOF
// ================================================
// 🧠 Neo4j Memory Backup - Terminal System v4.0
// ================================================
// Data: $(date)
// Nós: ${NODE_COUNT}
// Relacionamentos: ${REL_COUNT}
// Versão: 4.0-enhanced
// ================================================
// Para restaurar:
// 1. docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH (n) DETACH DELETE n;"
// 2. docker exec -i terminal-neo4j cypher-shell -u neo4j -p password < backup.cypher
// ================================================

EOF

log "${YELLOW}📝 Exportando nós...${NC}"

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
log "${YELLOW}📝 Exportando relacionamentos...${NC}"

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

log "${GREEN}✓ Comandos CREATE gerados: ${LINES_CREATE}${NC}"
log "${GREEN}✓ Comandos MATCH gerados: ${LINES_MATCH}${NC}"

# Criar metadata aprimorada
METADATA_FILE="/tmp/metadata_${TIMESTAMP}.json"
cat > "$METADATA_FILE" << EOF
{
    "timestamp": "${TIMESTAMP}",
    "date": "$(date)",
    "nodes": ${NODE_COUNT},
    "relationships": ${REL_COUNT},
    "create_commands": ${LINES_CREATE},
    "match_commands": ${LINES_MATCH},
    "backup_version": "4.0-enhanced",
    "neo4j_version": "$(docker exec terminal-neo4j neo4j version 2>/dev/null || echo 'unknown')",
    "container_id": "$(docker ps -q --filter name=terminal-neo4j)",
    "system_info": {
        "hostname": "$(hostname)",
        "user": "$(whoami)",
        "disk_usage": "$(df -h . | tail -1 | awk '{print $5}')"
    }
}
EOF

# Criar README aprimorado
README_FILE="/tmp/README_${TIMESTAMP}.txt"
cat > "$README_FILE" << EOF
Neo4j Backup - Terminal System v4.0 Enhanced
============================================
Data: $(date)
Nós: ${NODE_COUNT}
Relacionamentos: ${REL_COUNT}
Comandos CREATE: ${LINES_CREATE}
Comandos MATCH: ${LINES_MATCH}
Versão: 4.0-enhanced

Para restaurar:
1. unzip BACKUP_${TIMESTAMP}.zip
2. docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH (n) DETACH DELETE n;"
3. docker exec -i terminal-neo4j cypher-shell -u neo4j -p password < neo4j_backup_${TIMESTAMP}.cypher

Verificação:
- docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH (n) RETURN count(n);"
- docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH ()-[r]->() RETURN count(r);"

Log completo: $LOG_FILE
EOF

log "${YELLOW}📦 Criando arquivo ZIP...${NC}"

# Criar ZIP
cd /tmp
zip -q "$ZIP_FILE" \
    "neo4j_backup_${TIMESTAMP}.cypher" \
    "metadata_${TIMESTAMP}.json" \
    "README_${TIMESTAMP}.txt"

# Calcular hash do arquivo para verificação
ZIP_HASH=$(sha256sum "$ZIP_FILE" | cut -d' ' -f1)

log "${GREEN}╔══════════════════════════════════════════════╗${NC}"
log "${GREEN}║       ✅ Backup concluído com sucesso!       ║${NC}"
log "${GREEN}╚══════════════════════════════════════════════╝${NC}\n"

log "📦 Arquivo: ${CYAN}$(basename $ZIP_FILE)${NC}"
log "📊 Total: ${NODE_COUNT} nós, ${REL_COUNT} relacionamentos"
log "💾 Tamanho: $(du -h "$ZIP_FILE" | cut -f1)"
log "🔐 Hash SHA256: ${ZIP_HASH}"

# Verificar se o backup tem conteúdo
if [[ "${LINES_CREATE}" == "0" ]]; then
    log "\n${RED}⚠️ AVISO: Nenhum comando CREATE foi gerado!${NC}"
    log "${YELLOW}Verifique se o Neo4j tem dados.${NC}"
fi

log "\n${CYAN}📚 Últimos 3 backups:${NC}"
ls -lht "${BACKUP_DIR}"/*.zip 2>/dev/null | head -3

log "\n${BLUE}📅 Fim: $(date)${NC}"
log "${BLUE}⏱️ Duração: $((SECONDS)) segundos${NC}"

# Retornar informações para uso em scripts
echo "BACKUP_FILE=$ZIP_FILE"
echo "NODE_COUNT=$NODE_COUNT"
echo "REL_COUNT=$REL_COUNT"
echo "ZIP_HASH=$ZIP_HASH"
