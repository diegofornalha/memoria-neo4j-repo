// Neo4j Backup - Sistema Terminal
// Data: 2025-08-24
// Nós: 6 (5 originais + 1 Learning)

// Limpar banco (opcional)
// MATCH (n) DETACH DELETE n;

// Criar nós
CREATE (:Memory {
    name: "MCP Neo4j Agent Memory",
    type: "MCP_Configuration",
    container: "mcp-neo4j-agent",
    status: "Configurado via Docker",
    credentials: "neo4j/password",
    configuration: '{"method": "docker", "container_name": "mcp-neo4j-agent"}',
    created_at: datetime("2025-08-24T03:07:12.237Z"),
    updated_at: "2025-08-24T01:09:14.536603"
});

CREATE (:ProjectRules {
    name: "Diretrizes Terminal System",
    version: "2.0",
    active: true,
    created_at: datetime("2025-08-24T04:18:02.101Z"),
    updated_at: datetime("2025-08-24T04:18:02.101Z")
});

CREATE (:Rule {
    id: 1,
    title: "Sempre Consultar Neo4j",
    description: "Antes de qualquer ação, consultar o Neo4j para contexto completo",
    priority: "CRITICAL",
    implementation: "Usar Cypher queries para buscar informações relevantes"
});

CREATE (:Rule {
    id: 2,
    title: "Metodologia PRP - 100% Contexto",
    description: "Preservar, Recuperar e Processar - manter contexto completo do projeto",
    priority: "CRITICAL",
    implementation: "Todo conhecimento deve ser preservado no grafo antes de ser removido"
});

CREATE (:Rule {
    id: 3,
    title: "Documentação Direto no Neo4j",
    description: "NUNCA criar arquivos .md - toda documentação vai para o Neo4j",
    priority: "HIGH",
    implementation: "Usar nós com label Documentation ao invés de arquivos markdown",
    exception: "Apenas README.md principal e CLAUDE.md são permitidos"
});

CREATE (:Learning {
    name: "Aprendizado Sistema Backup",
    date: "2025-08-24",
    type: "system_improvement",
    lesson: "Backup deve exportar em formato CREATE válido do Cypher",
    problem: "Perdemos 30 nós porque formato não era compatível",
    solution: "Usar comandos CREATE explícitos",
    current_state: "6 nós preservados e funcionando"
});
