# ARCHIVADO — Ambiente propio "Invoice Audit Agent" (invoice-audit-foundry2)

> **Estado: archivado, no se usa para la demo en vivo.**
> El repositorio ahora usa como guía principal el tenant de Caldova (ver `/deliverables` en la raíz del repo). Esta carpeta se conserva como referencia histórica y técnica de lo que se intentó construir, lo que funcionó, y por qué una parte no pudo completarse.

## Qué es esto

Un ambiente de demo completo construido desde cero en una suscripción sandbox de Microsoft (`ME-MngEnvMCAP947629-jzapatamarti-1`), con:

- `scripts/deploy.sh` + `scripts/teardown.sh` + `scripts/lib/common.sh`: automatización idempotente para crear todo el ambiente (cuenta Foundry, proyecto, modelos, Azure AI Search, Knowledge Base/Foundry IQ, Application Insights, el agente "invoice-audit-agent").
- `config.env` / `config.env.example`: configuración de nombres de recursos.
- `knowledge-docs/`: documentos de muestra (contrato MSA, registro de aprobaciones, facturas) usados como Knowledge Source del agente.
- `deliverables/`: el guion de demo completo (`.md` canónico + `.docx`), capturas reales, presentación de resumen (`.pptx`) y hoja de referencia rápida (`Cheat-Sheet`).

## Qué funcionó (validado con datos reales)

- **Capítulo 2 completo**: Build (Playground), Grounding (Foundry IQ / Knowledge, incluyendo cómo ver los documentos indexados reales vía Azure AI Search), Traces, Monitor (costo/tokens reales), Evaluations (evaluación recurrente real `weekly-quality-monitor`, evaluador custom real `contract-policy-evidence-compliance` con 7 dimensiones auto-generadas y una corrida real con resultado 67% overall / 83% en el criterio custom, incluyendo un caso de fallo real documentado: el agente alucinó evidencia citando un registro de aprobaciones que nunca recuperó), Red teaming (escaneo real con resultado 75% ASR en "Prohibited actions").
- **Capítulo 3, Secciones 1, 2 y 4**: identidad de agentes en Microsoft Entra Agent ID, un hallazgo real de Microsoft Defender for Cloud ("Microsoft Foundry resources should restrict network access"), y la acción de contención/auditoría (asignar owner + due date).

## Qué NO se pudo completar — Capítulo 3, Sección 3 (Mapa de relaciones / Attack Path Analysis)

El objetivo era mostrar un mapa visual real de Defender for Cloud (Attack Path Analysis / Cloud Security Explorer) conectando el agente expuesto a un recurso de datos sensibles — replicando el patrón que sí existe en el tenant de Caldova (identidad de OpenClaw → storage account "internalpayments", clasificado como sensible, con una cadena real de "Lateral Movement With Sensitive Data").

**Investigación realizada y hallazgo:**

1. Se confirmó que **Attack Path Analysis requiere una cadena real de 2+ saltos** hacia un recurso de datos clasificado como sensible por Defender — no basta con un solo hallazgo aislado ni con tiempo de espera. Un solo rol "Owner" excesivo asignado a la identidad del proyecto Foundry (probado y luego revertido) no fue suficiente, porque no existía ningún recurso de datos (storage account) en la cadena para que Defender pudiera marcar como "crítico".
2. Se intentó replicar la arquitectura exacta de Caldova: crear un Storage Account real en `rg-invoice-audit-demo`, conectarlo vía la identidad administrada del Search service existente, y subir un archivo de muestra con datos sensibles (SSN/tarjetas de prueba, estilo "internalpayments") para que Defender lo clasificara como sensible.
3. **Bloqueo real encontrado**: la suscripción sandbox de Microsoft (`ME-MngEnvMCAP947629...`) fuerza `publicNetworkAccess: Disabled` en cualquier Storage Account nuevo, de forma irreversible vía Azure CLI, REST API directa, o el blade de Networking del portal — ninguna combinación de parámetros (`Enabled`, redes seleccionadas, IP específica permitida) logró que se mantuviera. Se investigó exhaustivamente la causa:
   - Se revisaron todas las asignaciones de Azure Policy visibles (suscripción, resource group, grupo de administración raíz) — ninguna bloquea explícitamente esto.
   - Se revisaron "Deny Assignments" (mecanismo más fuerte que Policy) — existen 2 en la suscripción, pero ambas están scoped a otros resource groups (Azure Monitor Workspace y Application Insights auto-gestionados), no al nuestro.
   - Se revisaron feature flags de la suscripción — nada relevante.
   - **Conclusión**: el bloqueo no es una Azure Policy visible ni exceptuable por un Owner de suscripción — es gobernanza corporativa de Microsoft aplicada a nivel de plataforma sobre todas las suscripciones sandbox de empleados (tipo `MngEnvMCAP`), diseñada para impedir que se expongan datos públicamente desde un ambiente de pruebas interno. No es solicitable como excepción por un administrador normal de la suscripción.
4. Como curiosidad técnica: sí fue posible **crear el container de blobs** (operación de plano de gestión/ARM), pero **no subir el archivo** (operación de plano de datos, bloqueada por la red).

**Por qué se abandonó este camino**: no es un problema de tiempo ni de configuración — es un límite estructural del tenant sandbox que no se puede sortear sin intervención de gobernanza corporativa de Microsoft (fuera del alcance de este proyecto). Se decidió usar el tenant de Caldova (que sí tiene esta condición ya construida y funcionando) como fuente real para la Sección 3 del Capítulo 3, en vez de seguir forzando este ambiente.

## Recursos Azure que quedaron en este intento (pendientes de limpieza si ya no se usan)

- Resource group: `rg-invoice-audit-demo` (suscripción `dde51996-0311-4cae-9195-5f943bd41bc5`)
- Storage Account de prueba: `stinvoiceaudit87b43b` (con 1 container `internalpayments`, vacío — nunca se pudo subir el archivo de datos sensibles)
- El rol "Owner" excesivo que se había asignado a la identidad del proyecto Foundry sobre el resource group ya fue retirado.
- Para eliminar todo el ambiente: `scripts/teardown.sh config.env` (ver script en esta misma carpeta archivada).
