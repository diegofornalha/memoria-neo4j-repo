#!/bin/bash
# 🧠 Neo4j Manager - Sistema de Gerenciamento
# Interface unificada para operações do Neo4j

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
PURPLE='\033[0;35m'
NC='\033[0m'

# Função para mostrar menu
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      🧠 Neo4j Manager System v1.0           ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}📊 Status do Sistema:${NC}"
    if docker ps | grep -q terminal-neo4j; then
        echo -e "  ${GREEN}✅ Neo4j: Rodando${NC}"
        
        # Verificar conectividade
        if docker exec terminal-neo4j cypher-shell -u neo4j -p password "RETURN 1;" --format plain >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅ Conectividade: OK${NC}"
            
            # Estatísticas
            NODE_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
                "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1 || echo "0")
            REL_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
                "MATCH ()-[r]->() RETURN count(r) as c;" --format plain 2>/dev/null | tail -1 || echo "0")
            
            echo -e "  📈 Nós: ${NODE_COUNT}"
            echo -e "  🔗 Relacionamentos: ${REL_COUNT}"
        else
            echo -e "  ${RED}❌ Conectividade: Falha${NC}"
        fi
    else
        echo -e "  ${RED}❌ Neo4j: Parado${NC}"
    fi
    
    # Verificar backups
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.zip 2>/dev/null | wc -l || echo "0")
    echo -e "  📦 Backups: ${BACKUP_COUNT} arquivos\n"
    
    echo -e "${PURPLE}🔧 Operações Disponíveis:${NC}"
    echo -e "  ${CYAN}1.${NC} 📦 Fazer Backup"
    echo -e "  ${CYAN}2.${NC} 🔄 Restaurar Backup"
    echo -e "  ${CYAN}3.${NC} 📚 Listar Backups"
    echo -e "  ${CYAN}4.${NC} 🔍 Verificar Status"
    echo -e "  ${CYAN}5.${NC} 🗑️ Limpar Banco"
    echo -e "  ${CYAN}6.${NC} 🌐 Abrir Browser"
    echo -e "  ${CYAN}7.${NC} 📊 Estatísticas Detalhadas"
    echo -e "  ${CYAN}8.${NC} 🧹 Limpar Backups Antigos"
    echo -e "  ${CYAN}0.${NC} 🚪 Sair\n"
}

# Função para fazer backup
do_backup() {
    echo -e "\n${YELLOW}📦 Iniciando backup...${NC}"
    if [[ -f "neo4j-backup-enhanced.sh" ]]; then
        ./neo4j-backup-enhanced.sh
    elif [[ -f "neo4j-backup.sh" ]]; then
        ./neo4j-backup.sh
    else
        echo -e "${RED}❌ Script de backup não encontrado!${NC}"
        return 1
    fi
    echo -e "\n${GREEN}✅ Backup concluído!${NC}"
    read -p "Pressione Enter para continuar..."
}

# Função para restaurar backup
do_restore() {
    echo -e "\n${YELLOW}🔄 Iniciando restauração...${NC}"
    if [[ -f "neo4j-restore.sh" ]]; then
        ./neo4j-restore.sh
    else
        echo -e "${RED}❌ Script de restauração não encontrado!${NC}"
        return 1
    fi
    echo -e "\n${GREEN}✅ Restauração concluída!${NC}"
    read -p "Pressione Enter para continuar..."
}

# Função para listar backups
list_backups() {
    echo -e "\n${BLUE}📚 Backups disponíveis:${NC}\n"
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR"/*.zip 2>/dev/null)" ]]; then
        echo -e "${YELLOW}Nenhum backup encontrado.${NC}"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    cd "$BACKUP_DIR"
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Nº │ Arquivo                    │ Tamanho │ Data/Hora           │${NC}"
    echo -e "${CYAN}├────┼────────────────────────────┼─────────┼─────────────────────┤${NC}"
    
    i=1
    for backup in $(ls -t BACKUP_*.zip 2>/dev/null); do
        size=$(du -h "$backup" | cut -f1)
        date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
        name=$(basename "$backup")
        printf "${CYAN}│${NC} %2d ${CYAN}│${NC} %-28s ${CYAN}│${NC} %7s ${CYAN}│${NC} %-19s ${CYAN}│${NC}\n" "$i" "$name" "$size" "$date"
        ((i++))
    done
    
    echo -e "${CYAN}└────┴────────────────────────────┴─────────┴─────────────────────┘${NC}"
    read -p "Pressione Enter para continuar..."
}

# Função para verificar status
check_status() {
    echo -e "\n${BLUE}🔍 Verificação detalhada do sistema:${NC}\n"
    
    # Status do Docker
    echo -e "${YELLOW}🐳 Status do Docker:${NC}"
    if command -v docker >/dev/null 2>&1; then
        echo -e "  ✅ Docker instalado"
        if docker info >/dev/null 2>&1; then
            echo -e "  ✅ Docker rodando"
        else
            echo -e "  ❌ Docker não está rodando"
            return 1
        fi
    else
        echo -e "  ❌ Docker não instalado"
        return 1
    fi
    
    # Status do Neo4j
    echo -e "\n${YELLOW}🧠 Status do Neo4j:${NC}"
    if docker ps | grep -q terminal-neo4j; then
        echo -e "  ✅ Container rodando"
        
        # Informações do container
        CONTAINER_ID=$(docker ps -q --filter name=terminal-neo4j)
        CONTAINER_INFO=$(docker inspect "$CONTAINER_ID" 2>/dev/null)
        
        if [[ -n "$CONTAINER_INFO" ]]; then
            UPTIME=$(echo "$CONTAINER_INFO" | jq -r '.[0].State.StartedAt' 2>/dev/null || echo "desconhecido")
            STATUS=$(echo "$CONTAINER_INFO" | jq -r '.[0].State.Status' 2>/dev/null || echo "desconhecido")
            echo -e "  📅 Iniciado em: $UPTIME"
            echo -e "  🔄 Status: $STATUS"
        fi
        
        # Teste de conectividade
        if docker exec terminal-neo4j cypher-shell -u neo4j -p password "RETURN 1;" --format plain >/dev/null 2>&1; then
            echo -e "  ✅ Conectividade OK"
            
            # Versão do Neo4j
            NEO4J_VERSION=$(docker exec terminal-neo4j neo4j version 2>/dev/null || echo "desconhecida")
            echo -e "  📋 Versão: $NEO4J_VERSION"
            
            # Estatísticas
            NODE_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
                "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1 || echo "0")
            REL_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
                "MATCH ()-[r]->() RETURN count(r) as c;" --format plain 2>/dev/null | tail -1 || echo "0")
            
            echo -e "  📈 Nós: $NODE_COUNT"
            echo -e "  🔗 Relacionamentos: $REL_COUNT"
        else
            echo -e "  ❌ Falha na conectividade"
        fi
    else
        echo -e "  ❌ Container não está rodando"
    fi
    
    # Status dos backups
    echo -e "\n${YELLOW}📦 Status dos Backups:${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        echo -e "  ✅ Diretório existe: $BACKUP_DIR"
        BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.zip 2>/dev/null | wc -l || echo "0")
        echo -e "  📊 Total de backups: $BACKUP_COUNT"
        
        if [[ $BACKUP_COUNT -gt 0 ]]; then
            LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.zip 2>/dev/null | head -1)
            LATEST_SIZE=$(du -h "$LATEST_BACKUP" | cut -f1)
            LATEST_DATE=$(stat -c %y "$LATEST_BACKUP" | cut -d' ' -f1,2 | cut -d'.' -f1)
            echo -e "  🕒 Último backup: $LATEST_DATE ($LATEST_SIZE)"
        fi
    else
        echo -e "  ❌ Diretório não existe"
    fi
    
    # Status dos scripts
    echo -e "\n${YELLOW}📜 Status dos Scripts:${NC}"
    if [[ -f "neo4j-backup.sh" ]]; then
        echo -e "  ✅ Script de backup: disponível"
    else
        echo -e "  ❌ Script de backup: não encontrado"
    fi
    
    if [[ -f "neo4j-restore.sh" ]]; then
        echo -e "  ✅ Script de restauração: disponível"
    else
        echo -e "  ❌ Script de restauração: não encontrado"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Função para limpar banco
clear_database() {
    echo -e "\n${RED}⚠️ ATENÇÃO: Esta operação irá APAGAR todos os dados do Neo4j!${NC}"
    echo -e "${YELLOW}Deseja continuar? (s/N):${NC}"
    read -r confirm
    
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        echo -e "${YELLOW}❌ Operação cancelada.${NC}"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    echo -e "\n${YELLOW}🗑️ Limpando banco de dados...${NC}"
    
    # Fazer backup de segurança primeiro
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SAFETY_BACKUP="$BACKUP_DIR/SAFETY_BEFORE_CLEAR_${TIMESTAMP}.zip"
    
    CURRENT_NODES=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
        "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1 || echo "0")
    
    if [[ "$CURRENT_NODES" != "0" ]]; then
        echo -e "${YELLOW}💾 Criando backup de segurança...${NC}"
        ./neo4j-backup.sh >/dev/null 2>&1 || true
        echo -e "${GREEN}✅ Backup de segurança criado${NC}"
    fi
    
    # Limpar banco
    docker exec terminal-neo4j cypher-shell -u neo4j -p password "MATCH (n) DETACH DELETE n;" --format plain >/dev/null 2>&1 || true
    
    echo -e "${GREEN}✅ Banco de dados limpo!${NC}"
    read -p "Pressione Enter para continuar..."
}

# Função para abrir browser
open_browser() {
    echo -e "\n${BLUE}🌐 Abrindo Neo4j Browser...${NC}"
    echo -e "URL: ${CYAN}http://localhost:7474${NC}"
    echo -e "Credenciais: neo4j / password"
    
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "http://localhost:7474" >/dev/null 2>&1 &
        echo -e "${GREEN}✅ Browser aberto automaticamente${NC}"
    else
        echo -e "${YELLOW}ℹ️ Abra manualmente: http://localhost:7474${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Função para estatísticas detalhadas
detailed_stats() {
    echo -e "\n${BLUE}📊 Estatísticas detalhadas:${NC}\n"
    
    if ! docker ps | grep -q terminal-neo4j; then
        echo -e "${RED}❌ Neo4j não está rodando!${NC}"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    # Estatísticas básicas
    NODE_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
        "MATCH (n) RETURN count(n) as c;" --format plain 2>/dev/null | tail -1 || echo "0")
    REL_COUNT=$(docker exec terminal-neo4j cypher-shell -u neo4j -p password \
        "MATCH ()-[r]->() RETURN count(r) as c;" --format plain 2>/dev/null | tail -1 || echo "0")
    
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Estatísticas Gerais                                            │${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} Nós: %-55s ${CYAN}│${NC}\n" "$NODE_COUNT"
    printf "${CYAN}│${NC} Relacionamentos: %-45s ${CYAN}│${NC}\n" "$REL_COUNT"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    
    # Labels mais comuns
    echo -e "\n${YELLOW}🏷️ Labels mais comuns:${NC}"
    docker exec terminal-neo4j cypher-shell -u neo4j -p password \
        "CALL db.labels() YIELD label RETURN label, count(*) as count ORDER BY count DESC LIMIT 10;" \
        --format table 2>/dev/null || echo "Erro ao obter labels"
    
    # Tipos de relacionamento
    echo -e "\n${YELLOW}🔗 Tipos de relacionamento:${NC}"
    docker exec terminal-neo4j cypher-shell -u neo4j -p password \
        "CALL db.relationshipTypes() YIELD relationshipType RETURN relationshipType, count(*) as count ORDER BY count DESC LIMIT 10;" \
        --format table 2>/dev/null || echo "Erro ao obter relacionamentos"
    
    # Propriedades mais comuns
    echo -e "\n${YELLOW}📋 Propriedades mais comuns:${NC}"
    docker exec terminal-neo4j cypher-shell -u neo4j -p password \
        "CALL db.propertyKeys() YIELD propertyKey RETURN propertyKey, count(*) as count ORDER BY count DESC LIMIT 10;" \
        --format table 2>/dev/null || echo "Erro ao obter propriedades"
    
    read -p "Pressione Enter para continuar..."
}

# Função para limpar backups antigos
cleanup_backups() {
    echo -e "\n${YELLOW}🧹 Limpeza de backups antigos:${NC}\n"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo -e "${RED}❌ Diretório de backups não existe!${NC}"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.zip 2>/dev/null | wc -l || echo "0")
    
    if [[ $BACKUP_COUNT -eq 0 ]]; then
        echo -e "${YELLOW}ℹ️ Nenhum backup encontrado.${NC}"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    echo -e "Backups encontrados: $BACKUP_COUNT"
    echo -e "${YELLOW}Quantos backups manter? (padrão: 10):${NC}"
    read -r keep_count
    
    if [[ -z "$keep_count" ]]; then
        keep_count=10
    fi
    
    if ! [[ "$keep_count" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Valor inválido!${NC}"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    cd "$BACKUP_DIR"
    TO_DELETE=$(ls -t *.zip 2>/dev/null | tail -n +$((keep_count + 1)) | wc -l)
    
    if [[ $TO_DELETE -eq 0 ]]; then
        echo -e "${YELLOW}ℹ️ Nenhum backup para deletar.${NC}"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    echo -e "${RED}⚠️ Serão deletados $TO_DELETE backups antigos.${NC}"
    echo -e "${YELLOW}Confirmar? (s/N):${NC}"
    read -r confirm
    
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        echo -e "${YELLOW}❌ Operação cancelada.${NC}"
        read -p "Pressione Enter para continuar..."
        return
    fi
    
    ls -t *.zip 2>/dev/null | tail -n +$((keep_count + 1)) | xargs -r rm -f
    echo -e "${GREEN}✅ $TO_DELETE backups antigos removidos!${NC}"
    
    read -p "Pressione Enter para continuar..."
}

# Loop principal
while true; do
    show_menu
    echo -n "Escolha uma opção: "
    read -r choice
    
    case $choice in
        1) do_backup ;;
        2) do_restore ;;
        3) list_backups ;;
        4) check_status ;;
        5) clear_database ;;
        6) open_browser ;;
        7) detailed_stats ;;
        8) cleanup_backups ;;
        0) 
            echo -e "\n${GREEN}👋 Até logo!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}❌ Opção inválida!${NC}"
            read -p "Pressione Enter para continuar..."
            ;;
    esac
done
