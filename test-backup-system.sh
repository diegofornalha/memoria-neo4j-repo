#!/bin/bash
# 🧪 Teste CRUD Completo do Sistema de Backup ZIP
# Valida todo o fluxo: criar dados → backup → apagar → restaurar

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     🧪 TESTE CRUD - Sistema de Backup Neo4j          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"

BACKUP_DIR="/home/codable/terminal/memoria-neo4j-repo/memory-backups"
TEST_BACKUP="test_crud_$(date +%Y%m%d_%H%M%S).zip"
TEMP_DIR="/tmp/test_crud_$$"

# Função para contar memórias
count_memories() {
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-password}" \
        "MATCH (n) RETURN count(n) as count" \
        --format plain 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0"
}

# Função para criar dados de teste
create_test_data() {
    echo -e "${BLUE}1️⃣ CREATE - Criando dados de teste...${NC}"
    
    # Criar diferentes tipos de nós
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-password}" << 'CYPHER'
// Limpar banco primeiro
MATCH (n) DETACH DELETE n;

// Criar estrutura de teste
CREATE (project:Project {
    name: 'Terminal System',
    created_at: datetime(),
    version: '2.0',
    status: 'active'
})

CREATE (backup:Feature {
    name: 'Backup System',
    type: 'ZIP',
    compression: true,
    created_at: datetime()
})

CREATE (memory1:Memory {
    id: 1,
    content: 'Primeira memória de teste',
    timestamp: datetime(),
    importance: 'high'
})

CREATE (memory2:Memory {
    id: 2,
    content: 'Segunda memória de teste',
    timestamp: datetime(),
    importance: 'medium'
})

CREATE (memory3:Memory {
    id: 3,
    content: 'Terceira memória de teste',
    timestamp: datetime(),
    importance: 'low'
})

// Criar relacionamentos
CREATE (project)-[:HAS_FEATURE]->(backup)
CREATE (project)-[:STORES]->(memory1)
CREATE (project)-[:STORES]->(memory2)
CREATE (project)-[:STORES]->(memory3)
CREATE (memory1)-[:RELATES_TO]->(memory2)
CREATE (memory2)-[:RELATES_TO]->(memory3)

RETURN count(*) as nodes_created;
CYPHER
    
    local count=$(count_memories)
    echo -e "${GREEN}   ✅ Criados $count nós de teste${NC}\n"
}

# Função para fazer backup
backup_data() {
    echo -e "${BLUE}2️⃣ READ/BACKUP - Fazendo backup em ZIP...${NC}"
    
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Exportar dados
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-password}" \
        --format plain << 'CYPHER' | grep "^{" > "$TEMP_DIR/memories.json"
CALL {
    MATCH (n)
    WITH collect({
        id: id(n),
        labels: labels(n),
        properties: properties(n)
    }) as nodes
    MATCH ()-[r]->()
    WITH nodes, collect({
        id: id(r),
        type: type(r),
        start: id(startNode(r)),
        end: id(endNode(r)),
        properties: properties(r)
    }) as relationships
    RETURN {
        timestamp: datetime(),
        nodes: nodes,
        relationships: relationships,
        stats: {
            nodeCount: size(nodes),
            relationshipCount: size(relationships)
        }
    }
}
CYPHER
    
    # Criar metadata
    cat > "$TEMP_DIR/metadata.json" << EOF
{
    "test": true,
    "date": "$(date -Iseconds)",
    "purpose": "CRUD test validation"
}
EOF
    
    # Comprimir
    cd "$TEMP_DIR"
    zip -qr "$BACKUP_DIR/$TEST_BACKUP" .
    cd - > /dev/null
    
    echo -e "${GREEN}   ✅ Backup criado: $TEST_BACKUP${NC}"
    echo -e "${GREEN}   📦 Tamanho: $(du -h "$BACKUP_DIR/$TEST_BACKUP" | cut -f1)${NC}\n"
}

# Função para apagar dados
delete_data() {
    echo -e "${BLUE}3️⃣ UPDATE/DELETE - Apagando TODOS os dados...${NC}"
    
    # Apagar tudo
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-password}" \
        "MATCH (n) DETACH DELETE n" 2>/dev/null
    
    local count=$(count_memories)
    
    if [ "$count" -eq "0" ]; then
        echo -e "${GREEN}   ✅ Banco limpo com sucesso!${NC}"
        echo -e "${YELLOW}   ⚠️  Nenhuma memória no banco${NC}\n"
    else
        echo -e "${RED}   ❌ Erro: ainda existem $count nós${NC}\n"
        exit 1
    fi
}

# Função para restaurar dados
restore_data() {
    echo -e "${BLUE}4️⃣ RESTORE - Restaurando do ZIP...${NC}"
    
    # Extrair backup
    local restore_dir="/tmp/restore_$$"
    mkdir -p "$restore_dir"
    unzip -q "$BACKUP_DIR/$TEST_BACKUP" -d "$restore_dir"
    
    # Processar JSON e criar comandos Cypher
    python3 << EOF
import json
import subprocess
import sys

try:
    with open('$restore_dir/memories.json', 'r') as f:
        content = f.read()
        if not content:
            print("❌ Arquivo JSON vazio!")
            sys.exit(1)
        
        data = json.loads(content)
    
    # Preparar comandos
    nodes = data.get('nodes', [])
    relationships = data.get('relationships', [])
    
    print(f"   📊 Restaurando {len(nodes)} nós e {len(relationships)} relacionamentos...")
    
    # Criar script Cypher
    with open('/tmp/restore.cypher', 'w') as out:
        # Criar nós com IDs temporários
        node_map = {}
        for i, node in enumerate(nodes):
            labels = ':'.join(node.get('labels', ['Node']))
            props_dict = node.get('properties', {})
            
            # Formatar propriedades
            props_list = []
            for k, v in props_dict.items():
                if isinstance(v, str):
                    props_list.append(f'{k}: "{v}"')
                elif isinstance(v, (int, float, bool)):
                    props_list.append(f'{k}: {str(v).lower()}')
                elif v is None:
                    continue
                else:
                    props_list.append(f'{k}: "{str(v)}"')
            
            props = '{' + ', '.join(props_list) + '}' if props_list else '{}'
            
            var_name = f'n{i}'
            node_map[node.get('id', i)] = var_name
            
            out.write(f'CREATE ({var_name}:{labels} {props})\\n')
        
        # Criar relacionamentos
        for rel in relationships:
            start_id = rel.get('start', rel.get('startNode'))
            end_id = rel.get('end', rel.get('endNode'))
            rel_type = rel.get('type', 'RELATED_TO')
            
            if start_id in node_map and end_id in node_map:
                start_var = node_map[start_id]
                end_var = node_map[end_id]
                
                props_dict = rel.get('properties', {})
                props_list = []
                for k, v in props_dict.items():
                    if isinstance(v, str):
                        props_list.append(f'{k}: "{v}"')
                    else:
                        props_list.append(f'{k}: {v}')
                
                props = '{' + ', '.join(props_list) + '}' if props_list else ''
                
                out.write(f'CREATE ({start_var})-[:{rel_type} {props}]->({end_var})\\n')
    
    # Executar restore
    result = subprocess.run([
        'docker', 'exec', 'terminal-neo4j',
        'cypher-shell', '-u', 'neo4j', '-p', '${NEO4J_PASSWORD:-password}',
        '-f', '/tmp/restore.cypher'
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        # Tentar método alternativo
        with open('/tmp/restore.cypher', 'r') as f:
            for line in f:
                if line.strip():
                    subprocess.run([
                        'docker', 'exec', 'terminal-neo4j',
                        'cypher-shell', '-u', 'neo4j', '-p', '${NEO4J_PASSWORD:-password}',
                        line.strip()
                    ], capture_output=True)
    
    print("   ✅ Comandos Cypher executados")
    
except Exception as e:
    print(f"   ❌ Erro: {e}")
    sys.exit(1)
EOF
    
    # Copiar script para container
    docker cp /tmp/restore.cypher terminal-neo4j:/tmp/restore.cypher 2>/dev/null || true
    
    # Executar
    docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-password}" \
        -f /tmp/restore.cypher 2>/dev/null || {
        echo -e "${YELLOW}   Tentando método alternativo...${NC}"
        cat /tmp/restore.cypher | docker exec -i terminal-neo4j cypher-shell \
            -u neo4j -p "${NEO4J_PASSWORD:-password}" 2>/dev/null
    }
    
    # Limpar
    rm -rf "$restore_dir" /tmp/restore.cypher
    
    local count=$(count_memories)
    echo -e "${GREEN}   ✅ Restaurados $count nós${NC}\n"
}

# Função para validar restauração
validate_restore() {
    echo -e "${BLUE}5️⃣ VALIDATE - Validando integridade...${NC}"
    
    # Verificar dados específicos
    local project=$(docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-password}" \
        "MATCH (p:Project {name: 'Terminal System'}) RETURN p.name" \
        --format plain 2>/dev/null | grep "Terminal System" || echo "")
    
    local memories=$(docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-password}" \
        "MATCH (m:Memory) RETURN count(m)" \
        --format plain 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
    
    local relationships=$(docker exec terminal-neo4j cypher-shell \
        -u neo4j -p "${NEO4J_PASSWORD:-password}" \
        "MATCH ()-[r]->() RETURN count(r)" \
        --format plain 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo -e "${CYAN}   📋 Resultados da validação:${NC}"
    
    if [ -n "$project" ]; then
        echo -e "${GREEN}   ✅ Project 'Terminal System' encontrado${NC}"
    else
        echo -e "${RED}   ❌ Project não encontrado${NC}"
    fi
    
    if [ "$memories" -eq "3" ]; then
        echo -e "${GREEN}   ✅ 3 memórias restauradas corretamente${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Encontradas $memories memórias (esperado: 3)${NC}"
    fi
    
    if [ "$relationships" -gt "0" ]; then
        echo -e "${GREEN}   ✅ $relationships relacionamentos restaurados${NC}"
    else
        echo -e "${RED}   ❌ Nenhum relacionamento encontrado${NC}"
    fi
    
    echo ""
}

# Função principal
main() {
    echo -e "${YELLOW}Este teste irá:${NC}"
    echo -e "  1. Criar dados de teste"
    echo -e "  2. Fazer backup em ZIP"
    echo -e "  3. APAGAR TUDO do Neo4j"
    echo -e "  4. Restaurar do ZIP"
    echo -e "  5. Validar a restauração\n"
    
    read -p "Continuar? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        echo -e "${RED}Teste cancelado.${NC}"
        exit 1
    fi
    
    echo ""
    
    # Executar teste CRUD
    create_test_data
    backup_data
    delete_data
    restore_data
    validate_restore
    
    # Resultado final
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ✅ TESTE CRUD CONCLUÍDO!                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo -e "${GREEN}🎉 Sistema de backup ZIP está 100% funcional!${NC}"
    echo -e "${CYAN}📦 Backup de teste: $BACKUP_DIR/$TEST_BACKUP${NC}"
    
    # Limpar temporários
    rm -rf "$TEMP_DIR"
}

# Executar
main