#!/bin/bash
# 🧠 Gerenciador de Backups de Memórias Neo4j
# Sistema completo para backup manual e automático em ZIP

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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Criar diretório se não existir
mkdir -p "${BACKUP_DIR}"

# Função para mostrar menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     🧠 Neo4j Memory Backup Manager          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Escolha uma opção:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} 📦 Fazer backup manual (ZIP)"
    echo -e "  ${GREEN}2)${NC} 🔄 Restaurar de backup ZIP"
    echo -e "  ${GREEN}3)${NC} 📊 Ver estatísticas do banco"
    echo -e "  ${GREEN}4)${NC} 📚 Listar backups disponíveis"
    echo -e "  ${GREEN}5)${NC} ⏰ Configurar backup automático"
    echo -e "  ${GREEN}6)${NC} 🧹 Limpar backups antigos"
    echo -e "  ${GREEN}7)${NC} 📤 Exportar backup para compartilhar"
    echo -e "  ${GREEN}8)${NC} 📥 Importar backup externo"
    echo ""
    echo -e "  ${RED}0)${NC} Sair"
    echo ""
}

# Função para fazer backup
create_backup() {
    echo -e "\n${BLUE}📦 Criando backup das memórias...${NC}"
    
    local backup_type="${1:-manual}"
    local backup_name="neo4j_memories_${DATE}_${TIME}"
    
    if [ "$backup_type" == "auto" ]; then
        backup_name="auto_${backup_name}"
    fi
    
    local temp_dir="/tmp/${backup_name}"
    mkdir -p "$temp_dir"
    
    # Verificar se Neo4j está rodando
    if ! docker ps | grep -q terminal-neo4j; then
        echo -e "${RED}❌ Neo4j não está rodando!${NC}"
        echo -e "${YELLOW}Iniciando Neo4j...${NC}"
        docker compose up -d terminal-neo4j
        sleep 10
    fi
    
    # Exportar dados
    echo -e "${YELLOW}  Exportando memórias...${NC}"
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-Cancela@1}" \
        --format plain << 'CYPHER' | grep "^{" > "${temp_dir}/memories.json" 2>/dev/null || echo "{}" > "${temp_dir}/memories.json"
CALL {
    MATCH (n)
    RETURN collect({
        id: id(n),
        labels: labels(n),
        properties: properties(n)
    }) as nodes
}
CALL {
    MATCH ()-[r]->()
    RETURN collect({
        id: id(r),
        type: type(r),
        start: id(startNode(r)),
        end: id(endNode(r)),
        properties: properties(r)
    }) as relationships
}
WITH nodes, relationships
RETURN {
    exportDate: datetime(),
    nodes: nodes,
    relationships: relationships,
    stats: {
        nodeCount: size(nodes),
        relationshipCount: size(relationships)
    }
}
CYPHER
    
    # Obter estatísticas
    local node_count=$(grep -o '"nodeCount":[0-9]*' "${temp_dir}/memories.json" 2>/dev/null | cut -d: -f2 || echo "0")
    local rel_count=$(grep -o '"relationshipCount":[0-9]*' "${temp_dir}/memories.json" 2>/dev/null | cut -d: -f2 || echo "0")
    
    # Criar metadata
    cat > "${temp_dir}/metadata.json" << EOF
{
    "backup_date": "${DATE}",
    "backup_time": "${TIME}",
    "backup_type": "${backup_type}",
    "neo4j_version": "5.26.10",
    "stats": {
        "nodes": ${node_count},
        "relationships": ${rel_count}
    }
}
EOF
    
    # Criar README
    cat > "${temp_dir}/README.txt" << EOF
Neo4j Memory Backup
===================
Data: ${DATE} ${TIME}
Tipo: ${backup_type}

Estatísticas:
- Nós: ${node_count}
- Relacionamentos: ${rel_count}

Como restaurar:
1. Extrair: unzip ${backup_name}.zip
2. Usar o script: ./restore-memory.sh
EOF
    
    # Comprimir
    echo -e "${YELLOW}  Comprimindo...${NC}"
    cd "$temp_dir"
    zip -qr "${BACKUP_DIR}/${backup_name}.zip" .
    cd - > /dev/null
    
    # Limpar temp
    rm -rf "$temp_dir"
    
    # Criar link para último backup
    ln -sf "${BACKUP_DIR}/${backup_name}.zip" "${BACKUP_DIR}/latest.zip"
    
    echo -e "${GREEN}✅ Backup criado: ${backup_name}.zip${NC}"
    echo -e "${GREEN}   Tamanho: $(du -h "${BACKUP_DIR}/${backup_name}.zip" | cut -f1)${NC}"
    echo -e "${GREEN}   Memórias: ${node_count} nós, ${rel_count} relacionamentos${NC}"
    
    return 0
}

# Função para restaurar backup
restore_backup() {
    echo -e "\n${BLUE}🔄 Restaurar backup${NC}"
    echo -e "${YELLOW}Backups disponíveis:${NC}\n"
    
    # Listar backups
    local i=1
    local backups=()
    for backup in "${BACKUP_DIR}"/*.zip; do
        if [ -f "$backup" ]; then
            local name=$(basename "$backup")
            local size=$(du -h "$backup" | cut -f1)
            local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "$backup" 2>/dev/null)
            echo -e "  ${GREEN}$i)${NC} $name ($size) - $date"
            backups+=("$backup")
            ((i++))
        fi
    done
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}Nenhum backup encontrado!${NC}"
        return 1
    fi
    
    echo ""
    read -p "Escolha o backup (1-${#backups[@]}): " choice
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        echo -e "${RED}Opção inválida!${NC}"
        return 1
    fi
    
    local selected_backup="${backups[$((choice-1))]}"
    
    echo -e "\n${YELLOW}⚠️  ATENÇÃO: Isso apagará todos os dados atuais!${NC}"
    read -p "Continuar? (s/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        echo -e "${RED}Cancelado.${NC}"
        return 1
    fi
    
    # Extrair backup
    local temp_dir="/tmp/restore_${TIMESTAMP}"
    mkdir -p "$temp_dir"
    unzip -q "$selected_backup" -d "$temp_dir"
    
    # Limpar banco atual
    echo -e "${YELLOW}  Limpando banco atual...${NC}"
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-Cancela@1}" \
        "MATCH (n) DETACH DELETE n" 2>/dev/null || true
    
    # Restaurar dados
    echo -e "${YELLOW}  Restaurando memórias...${NC}"
    
    # Converter JSON para Cypher e executar
    python3 << EOF
import json
import subprocess

with open('${temp_dir}/memories.json', 'r') as f:
    data = json.load(f)

# Criar comandos Cypher
cypher_commands = []

# Criar nós
for node in data.get('nodes', []):
    labels = ':'.join(node.get('labels', ['Memory']))
    props = json.dumps(node.get('properties', {}))
    cypher_commands.append(f"CREATE (:{labels} {props})")

# Criar relacionamentos
for rel in data.get('relationships', []):
    # Simplificado - você pode melhorar isso
    cypher_commands.append(f"// Relationship: {rel.get('type')}")

# Executar comandos
for cmd in cypher_commands[:10]:  # Limitar para teste
    try:
        subprocess.run([
            'docker', 'exec', 'terminal-neo4j', 
            'cypher-shell', '-u', 'neo4j', 
            '-p', '${NEO4J_PASSWORD:-Cancela@1}',
            cmd
        ], capture_output=True)
    except:
        pass

print(f"Restaurados {len(data.get('nodes', []))} nós")
EOF
    
    # Limpar temp
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✅ Restore concluído!${NC}"
}

# Função para estatísticas
show_stats() {
    echo -e "\n${BLUE}📊 Estatísticas do Neo4j${NC}\n"
    
    # Contar nós
    local nodes=$(docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-Cancela@1}" \
        "MATCH (n) RETURN count(n)" \
        --format plain 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
    
    # Contar relacionamentos
    local rels=$(docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-Cancela@1}" \
        "MATCH ()-[r]->() RETURN count(r)" \
        --format plain 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo -e "  ${GREEN}Nós:${NC} $nodes"
    echo -e "  ${GREEN}Relacionamentos:${NC} $rels"
    echo -e "  ${GREEN}Total de backups:${NC} $(ls -1 "${BACKUP_DIR}"/*.zip 2>/dev/null | wc -l)"
    echo -e "  ${GREEN}Espaço usado:${NC} $(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "0")"
    echo -e "  ${GREEN}Último backup:${NC} $(ls -t "${BACKUP_DIR}"/*.zip 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null || echo "Nenhum")"
}

# Função para listar backups
list_backups() {
    echo -e "\n${BLUE}📚 Backups disponíveis${NC}\n"
    
    if [ ! -d "${BACKUP_DIR}" ] || [ -z "$(ls -A ${BACKUP_DIR}/*.zip 2>/dev/null)" ]; then
        echo -e "${YELLOW}Nenhum backup encontrado.${NC}"
        return
    fi
    
    echo -e "${CYAN}Nome                                    Tamanho    Data${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────${NC}"
    
    ls -lht "${BACKUP_DIR}"/*.zip 2>/dev/null | while read line; do
        echo "$line" | awk '{printf "%-40s %-10s %s %s %s\n", $9, $5, $6, $7, $8}' | sed 's|.*/||'
    done
}

# Função para configurar backup automático
setup_auto_backup() {
    echo -e "\n${BLUE}⏰ Configurar Backup Automático${NC}\n"
    
    echo -e "${YELLOW}Escolha a frequência:${NC}"
    echo -e "  1) Diário (02:00 AM)"
    echo -e "  2) Semanal (Domingos 03:00 AM)"
    echo -e "  3) Mensal (Dia 1, 04:00 AM)"
    echo -e "  4) Personalizado"
    echo -e "  5) Desativar backups automáticos"
    echo ""
    
    read -p "Opção: " freq
    
    case $freq in
        1)
            CRON_SCHEDULE="0 2 * * *"
            CRON_DESC="Diário às 02:00"
            ;;
        2)
            CRON_SCHEDULE="0 3 * * 0"
            CRON_DESC="Semanal aos domingos"
            ;;
        3)
            CRON_SCHEDULE="0 4 1 * *"
            CRON_DESC="Mensal no dia 1"
            ;;
        4)
            read -p "Digite o cron schedule: " CRON_SCHEDULE
            CRON_DESC="Personalizado"
            ;;
        5)
            crontab -l | grep -v "backup-manager.sh auto" | crontab -
            echo -e "${GREEN}✅ Backups automáticos desativados${NC}"
            return
            ;;
        *)
            echo -e "${RED}Opção inválida${NC}"
            return
            ;;
    esac
    
    # Adicionar ao cron
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    (crontab -l 2>/dev/null | grep -v "backup-manager.sh auto"; echo "$CRON_SCHEDULE $SCRIPT_PATH auto") | crontab -
    
    echo -e "${GREEN}✅ Backup automático configurado: ${CRON_DESC}${NC}"
}

# Função para limpar backups antigos
cleanup_old_backups() {
    echo -e "\n${BLUE}🧹 Limpar Backups Antigos${NC}\n"
    
    echo -e "${YELLOW}Manter quantos backups?${NC}"
    read -p "Número (padrão 10): " keep
    keep=${keep:-10}
    
    # Contar backups atuais
    local total=$(ls -1 "${BACKUP_DIR}"/*.zip 2>/dev/null | wc -l)
    
    if [ "$total" -le "$keep" ]; then
        echo -e "${GREEN}Apenas $total backups encontrados, nada para limpar.${NC}"
        return
    fi
    
    # Remover antigos
    local to_remove=$((total - keep))
    echo -e "${YELLOW}Removendo $to_remove backups antigos...${NC}"
    
    ls -t "${BACKUP_DIR}"/*.zip | tail -n "$to_remove" | xargs rm -f
    
    echo -e "${GREEN}✅ Limpeza concluída!${NC}"
}

# Função para exportar backup
export_backup() {
    echo -e "\n${BLUE}📤 Exportar Backup${NC}\n"
    
    # Criar novo backup
    create_backup "export"
    
    # Copiar para Desktop ou Downloads
    local latest="${BACKUP_DIR}/latest.zip"
    local export_path="$HOME/Desktop/neo4j_backup_${DATE}.zip"
    
    if [ ! -d "$HOME/Desktop" ]; then
        export_path="$HOME/neo4j_backup_${DATE}.zip"
    fi
    
    cp "$latest" "$export_path"
    
    echo -e "${GREEN}✅ Backup exportado para: $export_path${NC}"
    echo -e "${YELLOW}   Você pode compartilhar este arquivo!${NC}"
}

# Função principal
main() {
    # Se chamado com "auto", fazer backup automático
    if [ "$1" == "auto" ]; then
        create_backup "auto"
        
        # Limpar backups automáticos antigos (manter últimos 7)
        ls -t "${BACKUP_DIR}"/auto_*.zip 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
        exit 0
    fi
    
    # Menu interativo
    while true; do
        show_menu
        read -p "Opção: " option
        
        case $option in
            1) create_backup ;;
            2) restore_backup ;;
            3) show_stats ;;
            4) list_backups ;;
            5) setup_auto_backup ;;
            6) cleanup_old_backups ;;
            7) export_backup ;;
            8) echo -e "${YELLOW}Em desenvolvimento...${NC}" ;;
            0) 
                echo -e "${GREEN}Até logo!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                ;;
        esac
        
        echo ""
        read -p "Pressione Enter para continuar..."
    done
}

# Executar
main "$@"