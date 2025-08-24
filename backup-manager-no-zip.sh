#!/bin/bash
# 🧠 Gerenciador de Backups de Memórias Neo4j - Versão SEM ZIP
# Sistema de backup direto em arquivos .cypher

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configurações
BACKUP_DIR="/home/codable/terminal/memoria-neo4j-repo/memory-backups"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H-%M-%S)
TIMESTAMP="${DATE}_${TIME}"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-password}"

# Criar diretório se não existir
mkdir -p "${BACKUP_DIR}"

# Função para mostrar menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     🧠 Neo4j Memory Backup Manager (NO ZIP) ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Escolha uma opção:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} 📦 Fazer backup (arquivos .cypher)"
    echo -e "  ${GREEN}2)${NC} 🔄 Restaurar de backup"
    echo -e "  ${GREEN}3)${NC} 📊 Ver estatísticas do banco"
    echo -e "  ${GREEN}4)${NC} 📚 Listar backups disponíveis"
    echo -e "  ${GREEN}5)${NC} 🧹 Limpar backups antigos (>7 dias)"
    echo ""
    echo -e "  ${RED}0)${NC} Sair"
    echo ""
}

# Função para fazer backup em arquivo .cypher
create_backup() {
    echo -e "\n${BLUE}📦 Criando backup das memórias em formato Cypher...${NC}"
    
    local backup_type="${1:-manual}"
    local backup_name="${backup_type}_backup_${TIMESTAMP}"
    local backup_file="${BACKUP_DIR}/${backup_name}.cypher"
    local metadata_file="${BACKUP_DIR}/${backup_name}_metadata.json"
    
    # Verificar se Neo4j está rodando
    if ! docker ps | grep -q terminal-neo4j; then
        echo -e "${RED}❌ Neo4j não está rodando!${NC}"
        echo -e "${YELLOW}Iniciando Neo4j...${NC}"
        docker compose up -d terminal-neo4j
        sleep 10
    fi
    
    echo -e "${YELLOW}  Exportando dados do Neo4j...${NC}"
    
    # Criar cabeçalho do arquivo
    cat > "$backup_file" << EOF
// Neo4j Memory Backup
// Data: ${DATE} ${TIME}
// Tipo: ${backup_type}
// ===========================================

// Limpar banco antes de restaurar (OPCIONAL - comente se quiser manter dados existentes)
// MATCH (n) DETACH DELETE n;

EOF
    
    # Exportar todos os nós e relacionamentos como comandos CREATE
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" \
        --format plain << 'CYPHER' >> "$backup_file" 2>/dev/null
// Exportar nós
MATCH (n)
WITH n, labels(n) as lbls, properties(n) as props
RETURN 
    'CREATE (n:' + 
    reduce(s = head(lbls), l IN tail(lbls) | s + ':' + l) + 
    ' ' + 
    CASE WHEN size(keys(props)) > 0 
         THEN apoc.convert.toJson(props)
         ELSE '{}' 
    END + 
    ');' as cypher
ORDER BY id(n);
CYPHER

    # Adicionar relacionamentos
    echo -e "\n// Relacionamentos" >> "$backup_file"
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" \
        --format plain << 'CYPHER' >> "$backup_file" 2>/dev/null
// Exportar relacionamentos
MATCH (a)-[r]->(b)
WITH a, r, b, type(r) as relType, properties(r) as props
RETURN 
    'MATCH (a), (b) WHERE id(a) = ' + id(a) + ' AND id(b) = ' + id(b) +
    ' CREATE (a)-[:' + relType + 
    CASE WHEN size(keys(props)) > 0 
         THEN ' ' + apoc.convert.toJson(props)
         ELSE '' 
    END + 
    ']->(b);' as cypher
ORDER BY id(r);
CYPHER

    # Obter estatísticas
    local stats=$(docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" \
        --format plain << 'CYPHER' 2>/dev/null
MATCH (n)
WITH count(n) as nodeCount
MATCH ()-[r]->()
RETURN nodeCount, count(r) as relCount;
CYPHER
    )
    
    local node_count=$(echo "$stats" | awk '{print $1}' | grep -E '^[0-9]+$' || echo "0")
    local rel_count=$(echo "$stats" | awk '{print $2}' | grep -E '^[0-9]+$' || echo "0")
    
    # Criar metadata
    cat > "$metadata_file" << EOF
{
    "backup_date": "${DATE}",
    "backup_time": "${TIME}",
    "backup_type": "${backup_type}",
    "backup_file": "${backup_name}.cypher",
    "neo4j_version": "5.x",
    "stats": {
        "nodes": ${node_count:-0},
        "relationships": ${rel_count:-0}
    }
}
EOF
    
    # Criar link para último backup
    ln -sf "${backup_name}.cypher" "${BACKUP_DIR}/latest.cypher"
    ln -sf "${backup_name}_metadata.json" "${BACKUP_DIR}/latest_metadata.json"
    
    echo -e "${GREEN}✅ Backup criado com sucesso!${NC}"
    echo -e "  📄 Arquivo: ${backup_file}"
    echo -e "  📊 Nós: ${node_count:-0}"
    echo -e "  🔗 Relacionamentos: ${rel_count:-0}"
}

# Função para restaurar backup
restore_backup() {
    echo -e "\n${BLUE}🔄 Restaurar backup${NC}"
    echo -e "${YELLOW}Backups disponíveis:${NC}\n"
    
    # Listar backups .cypher
    local backups=($(ls -1t "${BACKUP_DIR}"/*.cypher 2>/dev/null | grep -v latest.cypher | head -10))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}Nenhum backup encontrado!${NC}"
        return
    fi
    
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local name=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1)
        echo -e "  ${GREEN}$((i+1)))${NC} $name ($size) - $date"
    done
    
    echo ""
    read -p "Escolha o backup (1-${#backups[@]}): " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        echo -e "${RED}Opção inválida!${NC}"
        return
    fi
    
    local selected_backup="${backups[$((choice-1))]}"
    
    echo -e "\n${YELLOW}⚠️  ATENÇÃO: Isso apagará todos os dados atuais!${NC}"
    read -p "Confirmar restauração? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Operação cancelada.${NC}"
        return
    fi
    
    echo -e "${YELLOW}  Restaurando backup...${NC}"
    
    # Executar comandos Cypher
    docker exec -i terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" < "$selected_backup"
    
    echo -e "${GREEN}✅ Backup restaurado com sucesso!${NC}"
}

# Função para ver estatísticas
show_stats() {
    echo -e "\n${BLUE}📊 Estatísticas do Neo4j${NC}\n"
    
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" << 'CYPHER'
MATCH (n)
WITH count(n) as nodeCount, collect(DISTINCT labels(n)) as allLabels
MATCH ()-[r]->()
WITH nodeCount, allLabels, count(r) as relCount, collect(DISTINCT type(r)) as relTypes
RETURN 
    'Total de Nós: ' + nodeCount as metric,
    'Total de Relacionamentos: ' + relCount as value
UNION ALL
MATCH (n)
UNWIND labels(n) as label
WITH label, count(n) as cnt
RETURN 
    'Label: ' + label as metric,
    toString(cnt) + ' nós' as value
ORDER BY metric;
CYPHER
}

# Função para listar backups
list_backups() {
    echo -e "\n${BLUE}📚 Backups disponíveis${NC}\n"
    
    ls -lah "${BACKUP_DIR}"/*.cypher 2>/dev/null | grep -v latest.cypher || echo "Nenhum backup encontrado"
    
    echo -e "\n${CYAN}Último backup:${NC}"
    if [ -f "${BACKUP_DIR}/latest.cypher" ]; then
        ls -lah "${BACKUP_DIR}/latest.cypher"
    else
        echo "Nenhum"
    fi
}

# Função para limpar backups antigos
clean_old_backups() {
    echo -e "\n${YELLOW}🧹 Limpando backups com mais de 7 dias...${NC}"
    
    find "${BACKUP_DIR}" -name "*.cypher" -mtime +7 -type f | while read file; do
        echo -e "  Removendo: $(basename $file)"
        rm "$file"
        # Remover metadata correspondente
        rm -f "${file%.cypher}_metadata.json" 2>/dev/null
    done
    
    echo -e "${GREEN}✅ Limpeza concluída!${NC}"
}

# Menu principal
while true; do
    show_menu
    read -p "Opção: " option
    
    case $option in
        1)
            create_backup "manual"
            read -p "Pressione ENTER para continuar..."
            ;;
        2)
            restore_backup
            read -p "Pressione ENTER para continuar..."
            ;;
        3)
            show_stats
            read -p "Pressione ENTER para continuar..."
            ;;
        4)
            list_backups
            read -p "Pressione ENTER para continuar..."
            ;;
        5)
            clean_old_backups
            read -p "Pressione ENTER para continuar..."
            ;;
        0)
            echo -e "\n${GREEN}Até logo! 👋${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opção inválida!${NC}"
            sleep 2
            ;;
    esac
done