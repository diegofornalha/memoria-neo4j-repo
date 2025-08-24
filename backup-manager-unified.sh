#!/bin/bash
# 🧠 Gerenciador Unificado de Backups Neo4j
# Suporta ZIP e arquivos .cypher diretos

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
    echo -e "${CYAN}║  🧠 Neo4j Backup Manager - Unified Version  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Escolha uma opção:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} 📦 Criar backup COMPLETO (ZIP protegido)"
    echo -e "  ${GREEN}2)${NC} 📄 Criar backup SIMPLES (.cypher direto)"
    echo -e "  ${GREEN}3)${NC} 🔄 Restaurar backup (ZIP ou .cypher)"
    echo -e "  ${GREEN}4)${NC} 📊 Ver estatísticas do banco"
    echo -e "  ${GREEN}5)${NC} 📚 Listar todos os backups"
    echo -e "  ${GREEN}6)${NC} 🧹 Limpar backups antigos"
    echo ""
    echo -e "  ${RED}0)${NC} Sair"
    echo ""
}

# Função para criar backup completo com ZIP
create_complete_backup() {
    echo -e "\n${BLUE}📦 Criando backup COMPLETO com proteção ZIP...${NC}"
    
    local backup_name="neo4j_complete_backup_${TIMESTAMP}"
    local temp_dir="/tmp/${backup_name}"
    mkdir -p "$temp_dir"
    
    # Verificar se Neo4j está rodando
    if ! docker ps | grep -q terminal-neo4j; then
        echo -e "${RED}❌ Neo4j não está rodando!${NC}"
        echo -e "${YELLOW}Iniciando Neo4j...${NC}"
        docker compose up -d terminal-neo4j
        sleep 10
    fi
    
    echo -e "${YELLOW}  Exportando dados...${NC}"
    
    # 1. Exportar em formato Cypher
    cat > "$temp_dir/${backup_name}.cypher" << EOF
// ================================================
// 🧠 Neo4j Memory Backup - Terminal System
// ================================================
// Data: ${DATE} ${TIME}
// Tipo: Complete Backup (Protected)
// ================================================

// Para limpar banco antes de restaurar, descomente:
// MATCH (n) DETACH DELETE n;

// ========== DADOS EXPORTADOS ==========
EOF
    
    # Exportar nós em formato CREATE
    echo "// ========== CRIANDO NÓS ==========" >> "$temp_dir/${backup_name}.cypher"
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" \
        --format plain << 'CYPHER' >> "$temp_dir/${backup_name}.cypher" 2>/dev/null
MATCH (n)
WITH n, id(n) as nodeId, labels(n) as lbls, properties(n) as props
RETURN 
'CREATE (n' + nodeId + ':' + 
CASE WHEN size(lbls) > 0 
     THEN reduce(s = head(lbls), l IN tail(lbls) | s + ':' + l) 
     ELSE 'Node' 
END + ' {' +
CASE WHEN size(keys(props)) > 0 
     THEN reduce(s = '', k IN keys(props) | 
          s + CASE WHEN s = '' THEN '' ELSE ', ' END +
          k + ': ' + 
          CASE 
              WHEN props[k] IS NULL THEN 'null'
              WHEN type(props[k]) = 'STRING' THEN '"' + replace(replace(toString(props[k]), '\\', '\\\\'), '"', '\\"') + '"'
              WHEN type(props[k]) = 'BOOLEAN' THEN CASE WHEN props[k] THEN 'true' ELSE 'false' END
              ELSE toString(props[k])
          END
     )
     ELSE ''
END + '});' as cypher_command
ORDER BY nodeId;
CYPHER
    
    echo "" >> "$temp_dir/${backup_name}.cypher"
    echo "// ========== CRIANDO RELACIONAMENTOS ==========" >> "$temp_dir/${backup_name}.cypher"
    
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" \
        --format plain << 'CYPHER' >> "$temp_dir/${backup_name}.cypher" 2>/dev/null
MATCH (a)-[r]->(b)
WITH a, r, b, id(a) as aId, id(b) as bId, type(r) as relType, properties(r) as props
RETURN 
'MATCH (n' + aId + '), (n' + bId + ') ' +
'WHERE id(n' + aId + ') = ' + aId + ' AND id(n' + bId + ') = ' + bId + ' ' +
'CREATE (n' + aId + ')-[:' + relType +
CASE WHEN size(keys(props)) > 0
     THEN ' {' + reduce(s = '', k IN keys(props) |
          s + CASE WHEN s = '' THEN '' ELSE ', ' END +
          k + ': ' +
          CASE
              WHEN props[k] IS NULL THEN 'null'
              WHEN type(props[k]) = 'STRING' THEN '"' + replace(toString(props[k]), '"', '\\"') + '"'
              ELSE toString(props[k])
          END
     ) + '}'
     ELSE ''
END + ']->(n' + bId + ');' as cypher_command
ORDER BY id(r);
CYPHER
    
    # 2. Obter estatísticas
    local stats=$(docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" \
        "MATCH (n) WITH count(n) as nc MATCH ()-[r]->() RETURN nc, count(r);" --format plain 2>/dev/null | head -1)
    local node_count=$(echo "$stats" | awk '{print $1}')
    local rel_count=$(echo "$stats" | awk '{print $2}')
    
    # 3. Criar metadata
    cat > "$temp_dir/metadata.json" << EOF
{
    "backup_date": "${DATE}",
    "backup_time": "${TIME}",
    "backup_type": "complete_protected",
    "format": "zip_with_cypher",
    "neo4j_version": "5.x",
    "statistics": {
        "total_nodes": ${node_count:-0},
        "total_relationships": ${rel_count:-0}
    },
    "files": [
        "${backup_name}.cypher",
        "metadata.json",
        "README.txt"
    ]
}
EOF
    
    # 4. Criar README
    cat > "$temp_dir/README.txt" << EOF
Neo4j Complete Backup
=====================
Data: ${DATE} ${TIME}
Nodes: ${node_count:-0}
Relationships: ${rel_count:-0}

Como restaurar:
1. Extrair: unzip BACKUP_COMPLETO_NEO4J_${DATE//-/}.zip
2. Executar: docker exec -i terminal-neo4j cypher-shell -u neo4j -p password < ${backup_name}.cypher
EOF
    
    # 5. Verificar integridade do arquivo .cypher
    echo -e "${YELLOW}  Verificando integridade...${NC}"
    local cypher_size=$(du -b "$temp_dir/${backup_name}.cypher" | cut -f1)
    
    if [ "$cypher_size" -lt 100 ]; then
        echo -e "${RED}❌ Erro: Arquivo .cypher muito pequeno (${cypher_size} bytes)${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verificar se contém comandos CREATE
    if ! grep -q "^CREATE" "$temp_dir/${backup_name}.cypher"; then
        echo -e "${RED}❌ Erro: Arquivo não contém comandos CREATE válidos${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    echo -e "${GREEN}  ✅ Arquivo .cypher verificado (${cypher_size} bytes)${NC}"
    
    # 6. Zipar tudo
    echo -e "${YELLOW}  Comprimindo backup...${NC}"
    cd "$temp_dir"
    local zip_file="${BACKUP_DIR}/BACKUP_COMPLETO_NEO4J_${DATE//-/}_${TIME//:/-}.zip"
    zip -qr "$zip_file" .
    cd - > /dev/null
    
    # 7. Verificar ZIP criado
    if [ -f "$zip_file" ]; then
        echo -e "${GREEN}  ✅ ZIP criado com sucesso${NC}"
        # Limpar arquivos temporários e .cypher soltos
        rm -rf "$temp_dir"
        rm -f "${BACKUP_DIR}"/*.cypher 2>/dev/null
        echo -e "${CYAN}  🧹 Arquivos .cypher removidos (mantido apenas ZIP)${NC}"
    else
        echo -e "${RED}❌ Erro ao criar ZIP${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    echo -e "${GREEN}✅ Backup completo criado com sucesso!${NC}"
    echo -e "  📦 Arquivo: $zip_file"
    echo -e "  📊 Nós: ${node_count:-0} | Relacionamentos: ${rel_count:-0}"
    echo -e "  💾 Tamanho: $(du -h "$zip_file" | cut -f1)"
}

# Função para criar backup simples
create_simple_backup() {
    echo -e "\n${BLUE}📄 Criando backup simples (.cypher direto)...${NC}"
    
    local backup_file="${BACKUP_DIR}/backup_simples_${TIMESTAMP}.cypher"
    
    # Verificar Neo4j
    if ! docker ps | grep -q terminal-neo4j; then
        echo -e "${RED}❌ Neo4j não está rodando!${NC}"
        return
    fi
    
    # Exportar dados
    echo -e "${YELLOW}  Exportando dados...${NC}"
    
    cat > "$backup_file" << EOF
// Backup Simples - ${DATE} ${TIME}
// Para restaurar: docker exec -i terminal-neo4j cypher-shell -u neo4j -p password < $(basename $backup_file)

EOF
    
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" \
        "MATCH (n) RETURN n;" --format plain >> "$backup_file" 2>/dev/null
    
    echo -e "${GREEN}✅ Backup simples criado!${NC}"
    echo -e "  📄 Arquivo: $backup_file"
    ls -lah "$backup_file"
}

# Função para restaurar backup
restore_backup() {
    echo -e "\n${BLUE}🔄 Restaurar backup${NC}"
    
    # Listar todos os backups
    local zip_files=($(ls -1t "${BACKUP_DIR}"/*.zip 2>/dev/null))
    local cypher_files=($(ls -1t "${BACKUP_DIR}"/*.cypher 2>/dev/null))
    
    if [ ${#zip_files[@]} -eq 0 ] && [ ${#cypher_files[@]} -eq 0 ]; then
        echo -e "${RED}Nenhum backup encontrado!${NC}"
        return
    fi
    
    local index=1
    declare -A backup_map
    
    # Listar ZIPs
    if [ ${#zip_files[@]} -gt 0 ]; then
        echo -e "\n${CYAN}📦 Backups ZIP (protegidos):${NC}"
        for file in "${zip_files[@]}"; do
            local name=$(basename "$file")
            local size=$(du -h "$file" | cut -f1)
            echo -e "  ${GREEN}${index})${NC} $name ($size)"
            backup_map[$index]="$file"
            ((index++))
        done
    fi
    
    # Listar CYPHERs
    if [ ${#cypher_files[@]} -gt 0 ]; then
        echo -e "\n${CYAN}📄 Backups CYPHER (diretos):${NC}"
        for file in "${cypher_files[@]}"; do
            local name=$(basename "$file")
            local size=$(du -h "$file" | cut -f1)
            echo -e "  ${GREEN}${index})${NC} $name ($size)"
            backup_map[$index]="$file"
            ((index++))
        done
    fi
    
    echo ""
    read -p "Escolha o backup (1-$((index-1))): " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ -z "${backup_map[$choice]}" ]; then
        echo -e "${RED}Opção inválida!${NC}"
        return
    fi
    
    local selected="${backup_map[$choice]}"
    
    echo -e "\n${YELLOW}⚠️  ATENÇÃO: Isso apagará todos os dados atuais!${NC}"
    read -p "Confirmar restauração? (y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Operação cancelada.${NC}"
        return
    fi
    
    echo -e "${YELLOW}  Restaurando backup...${NC}"
    
    # Verificar tipo de arquivo
    if [[ "$selected" == *.zip ]]; then
        # Extrair ZIP
        local temp_restore="/tmp/restore_$$"
        mkdir -p "$temp_restore"
        unzip -q "$selected" -d "$temp_restore"
        
        # Procurar arquivo .cypher
        local cypher_file=$(find "$temp_restore" -name "*.cypher" | head -1)
        
        if [ -z "$cypher_file" ]; then
            echo -e "${RED}Arquivo .cypher não encontrado no ZIP!${NC}"
            rm -rf "$temp_restore"
            return
        fi
        
        # Restaurar
        docker exec -i terminal-neo4j cypher-shell \
            -u neo4j -p "${NEO4J_PASSWORD}" < "$cypher_file"
        
        # Limpar
        rm -rf "$temp_restore"
    else
        # Restaurar .cypher direto
        docker exec -i terminal-neo4j cypher-shell \
            -u neo4j -p "${NEO4J_PASSWORD}" < "$selected"
    fi
    
    echo -e "${GREEN}✅ Backup restaurado com sucesso!${NC}"
}

# Função para ver estatísticas
show_stats() {
    echo -e "\n${BLUE}📊 Estatísticas do Neo4j${NC}\n"
    
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD}" << 'CYPHER'
MATCH (n)
WITH count(n) as nodeCount
MATCH ()-[r]->()
WITH nodeCount, count(r) as relCount
MATCH (n)
UNWIND labels(n) as label
WITH nodeCount, relCount, label, count(*) as labelCount
ORDER BY labelCount DESC
RETURN 
    'Total de Nós' as Métrica, 
    toString(nodeCount) as Valor
UNION ALL
RETURN 
    'Total de Relacionamentos' as Métrica,
    toString(relCount) as Valor
UNION ALL
MATCH (n)
UNWIND labels(n) as label
WITH label, count(*) as cnt
RETURN 
    'Label: ' + label as Métrica,
    toString(cnt) + ' nós' as Valor
ORDER BY cnt DESC;
CYPHER
}

# Função para listar backups
list_backups() {
    echo -e "\n${BLUE}📚 Todos os backups disponíveis${NC}\n"
    
    echo -e "${CYAN}📦 Backups ZIP:${NC}"
    ls -lah "${BACKUP_DIR}"/*.zip 2>/dev/null || echo "  Nenhum"
    
    echo -e "\n${CYAN}📄 Backups CYPHER:${NC}"
    ls -lah "${BACKUP_DIR}"/*.cypher 2>/dev/null || echo "  Nenhum"
    
    echo -e "\n${YELLOW}Espaço total usado:${NC}"
    du -sh "${BACKUP_DIR}"
}

# Função para limpar backups antigos
clean_old_backups() {
    echo -e "\n${YELLOW}🧹 Limpando backups com mais de 7 dias...${NC}"
    
    # Manter sempre o BACKUP_COMPLETO mais recente
    local newest_complete=$(ls -1t "${BACKUP_DIR}"/BACKUP_COMPLETO_*.zip 2>/dev/null | head -1)
    
    # Limpar arquivos antigos
    find "${BACKUP_DIR}" -type f \( -name "*.zip" -o -name "*.cypher" \) -mtime +7 | while read file; do
        if [ "$file" != "$newest_complete" ]; then
            echo -e "  Removendo: $(basename $file)"
            rm "$file"
        fi
    done
    
    echo -e "${GREEN}✅ Limpeza concluída!${NC}"
}

# Menu principal
while true; do
    show_menu
    read -p "Opção: " option
    
    case $option in
        1)
            create_complete_backup
            read -p "Pressione ENTER para continuar..."
            ;;
        2)
            create_simple_backup
            read -p "Pressione ENTER para continuar..."
            ;;
        3)
            restore_backup
            read -p "Pressione ENTER para continuar..."
            ;;
        4)
            show_stats
            read -p "Pressione ENTER para continuar..."
            ;;
        5)
            list_backups
            read -p "Pressione ENTER para continuar..."
            ;;
        6)
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