# Guion de Demo — Microsoft Foundry en el Tenant Caldova
### Capítulo 2 (Observabilidad/Build) + Capítulo 3 (Seguridad y Gobierno de Agentes)

---

## 0. Contexto y por qué este guion usa el tenant Caldova

Este repositorio originalmente construía un entorno propio (`invoice-audit-foundry2`) para demostrar
Foundry de punta a punta, incluyendo el escenario de seguridad con **Attack Path / mapa de
relaciones** en Defender for Cloud. Ese entorno quedó **archivado** en
[`archived/invoice-audit-foundry-env/`](../archived/invoice-audit-foundry-env/README-ARCHIVED.md)
porque las subscripciones sandbox de Microsoft (`ME-MngEnvMCAP...`) fuerzan
`publicNetworkAccess: Disabled` en toda Storage Account nueva, a nivel de plataforma, sin política
exportable ni excepción posible — esto bloqueaba subir datos sensibles a un Storage Account y, con
ello, impedía poblar el grafo de ataque con una ruta real.

El tenant **Caldova** (`admin@caldova50800867.onmicrosoft.com`) ya tiene el escenario completo
construido y con datos reales: agentes operando sobre una base de conocimiento real (Foundry IQ +
Azure AI Search + Blob Storage), con hallazgos de seguridad ya poblados en Defender for Cloud. Por
eso este guion **usa Caldova como ambiente de demo**, documentando navegación real, capturas reales
y el valor de negocio de cada parada.

**Cuenta a usar:** `admin@caldova50800867.onmicrosoft.com` (acceso administrador completo al tenant).
**Proyecto Foundry:** `ai-project-waypoint-agents-goksdrsh`
**Recurso Foundry:** `ai-waypoint-agents-goksdrsh-9d71dfce`
**Resource Group:** `rg-waypoint-agents-goksdrsh`
**Suscripción:** `320f8985-146e-4137-95f6-ea653cec3685`

⚠️ **Caveat a validar antes del día de la demo:** durante el rehearsal (26-oct), enviar un mensaje de
prueba en Playground a `invoice-analyst` y a `assurance-orchestrator` falló (ver sección 2.5). La
causa más probable, confirmada en pantalla, es un aviso de permisos del managed identity del Search
service sobre el modelo (sección 2.3). **Antes de la demo real: volver a probar el chat en vivo** y,
si sigue fallando, apoyarse en las capturas de Monitor/Traces (que sí muestran actividad real) en
vez de un chat en vivo.

---

## CAPÍTULO 2 — Observabilidad y ciclo de vida de agentes (Build → Operate)

### 2.1 — Catálogo de agentes multi-agente

**Objetivo de la sección:** mostrar que no es "un" agente sino una arquitectura de **orquestación
multi-agente**, cada uno con un rol especializado.

**Navegación:** `ai.azure.com` → proyecto `ai-project-waypoint-agents-goksdrsh` → menú lateral
**Agents**.

**Qué mostrar en pantalla:** la lista de 7 agentes:
- `waypoint-recorder`
- `operations-data-expert`
- `market-evidence-expert`
- `contract-policy-expert`
- `collaboration-evidence-expert`
- `assurance-orchestrator` ← orquestador
- `invoice-analyst` ← agente principal de la demo

**Captura:** `screenshots/01-build-agents-list.png`

**Mensaje de valor para el cliente:** *"Esto no es un solo chatbot: es un patrón de orquestación
donde un agente coordinador (`assurance-orchestrator`) delega en agentes expertos especializados por
dominio (contratos, operaciones, evidencia de mercado, colaboración). Así es como se construyen
soluciones de IA de nivel empresarial — no un prompt gigante, sino composición de agentes."*

---

### 2.2 — Identidad real del agente (Build)

**Objetivo de la sección:** mostrar que cada agente no es solo configuración de prompt, sino una
**identidad de Entra ID** real y auditable.

**Navegación:** Agents → `invoice-analyst` → pestaña **Details**.

**Qué mostrar en pantalla:** el bloque de identidad del agente mostrando su **Entra Agent Identity**
(`invoice-analyst-AgentIdentity`) y su Blueprint asociado.

**Captura:** `screenshots/14-entra-agent-identity.png`

**Mensaje de valor para el cliente:** *"Cada agente que publicas en Foundry recibe automáticamente
una identidad de Entra ID — no es una cuenta de servicio compartida ni una API key suelta. Esto es
lo que permite después, en el Capítulo 3, rastrear exactamente qué agente tocó qué recurso."*

---

### 2.3 — Grounding real: Knowledge (Foundry IQ) sobre Azure AI Search + Blob Storage

**Objetivo de la sección:** mostrar que el agente no alucina — responde con **grounding real** sobre
documentos de la empresa (contratos de proveedores), usando Foundry IQ.

**Navegación:** menú lateral **Knowledge** → conexión `azure-ai-search-connection` → base de
conocimiento `contracts-kb`.

**Qué mostrar en pantalla (paso 1):** el listado de Knowledge Bases, con `contracts-kb` en estado
**Active**, conectada vía `azure-ai-search-connection`.

**Captura:** `screenshots/06-knowledge-search-connection.png`

**Qué mostrar en pantalla (paso 2):** abrir `contracts-kb` → configuración completa: modelo de chat
(`gpt-5-mini`), instrucciones de respuesta ("Answer with concise contract evidence. Cite source
documents and clause/section names..."), y la tabla **Knowledge sources (Foundry IQ)** mostrando
`contracts-ks` de tipo **Azure Blob Storage**, estado **Active**.

**Captura:** `screenshots/07-contracts-kb-detail.png`

**Qué mostrar en pantalla (paso 3 — opcional, técnico):** clic en `contracts-ks` para abrir el
detalle del origen: tipo "Azure Blob Storage — Retrieve documents and files from Azure Blob
Storage", contenedor `knowledge`, modelo de embeddings `text-embedding-3-large`.

**Captura:** `screenshots/08-knowledge-source-blob-detail.png`

**Mensaje de valor para el cliente:** *"El agente no inventa respuestas: está conectado a Azure AI
Search, que a su vez indexa documentos reales guardados en un Storage Account — en este caso,
contratos de proveedores de Ledgerfield. Esta es la misma arquitectura (Search + Managed Identity +
Blob Storage) que verán conectada al mapa de seguridad en el Capítulo 3."*

⚠️ **Nota para quien presente:** en este panel aparece un aviso ámbar: *"We couldn't verify the
search service's managed identity permissions for this model. An administrator can confirm its
effective access..."*. Es el punto exacto a revisar/resolver antes de depender de un chat en vivo en
el Capítulo 2 (ver 2.5).

---

### 2.4 — Trazabilidad de ejecución (Traces)

**Objetivo de la sección:** mostrar que cada interacción del agente queda registrada paso a paso,
no es una "caja negra".

**Navegación:** Agents → `invoice-analyst` → pestaña **Traces**.

**Qué mostrar en pantalla:** la lista de ejecuciones (runs) con estado **Completed**, timestamps y
duración.

**Captura:** `screenshots/03-invoice-analyst-traces.png`

**Mensaje de valor para el cliente:** *"Todo lo que el agente hace queda trazado: qué herramienta
llamó, cuánto tardó, qué tokens consumió. Esto habilita debugging y auditoría — crítico quieran o no
para pasar una revisión de seguridad o de cumplimiento."*

---

### 2.5 — Intentar una conversación en vivo (y qué hacer si falla)

**Objetivo de la sección:** mostrar la experiencia conversacional real del agente.

**Navegación:** Agents → `invoice-analyst` (o `assurance-orchestrator`) → **Playground** → escribir
un mensaje de prueba, ej.: *"¿Qué cláusulas rigen el contrato del proveedor X?"*.

**Qué mostrar en pantalla (caso feliz):** la respuesta del agente citando evidencia del contrato.

**Qué pasó en el rehearsal (26-oct), documentado honestamente:** ambos agentes fallaron:
- `invoice-analyst`: error inmediato `ToolExecutionException: Failed to enter context manager`.
- `assurance-orchestrator`: ~90s de "Thinking..." (actividad real visible en logs — auth de managed
  identity, llamadas a MCP) y luego `Error network error`.

**Captura (evidencia del intento, no del éxito):**
`screenshots/02-invoice-analyst-playground-response.png`,
`screenshots/04-orchestrator-response-complete.png`

**Verificación de que el intento fue real (no un glitch de UI):** pestaña **Monitor** del proyecto
muestra la ejecución realmente registrada: 1 agent run, \$0 costo, 0 tokens (confirma que la llamada
al modelo nunca llegó a completarse — consistente con el aviso de permisos de 2.3).

**Captura:** `screenshots/05-orchestrator-monitor.png`

**Mensaje de valor para el cliente (si el chat en vivo funciona):** *"Así es como un usuario de
negocio interactúa con el agente — lenguaje natural, respuesta con evidencia citada."*

**Mensaje de valor para el cliente (si el chat en vivo sigue fallando el día de la demo):** *"Este
agente está operando sobre una arquitectura con controles de red y de identidad reales — lo que
estamos viendo aquí es precisamente la fricción que ocurre cuando esos controles están mal
configurados. Lo vamos a ver resuelto en Operate/Monitor, y es el mismo tipo de hallazgo que Defender
for Cloud va a señalar en el Capítulo 3."* (Giro honesto: convierte el fallo en gancho hacia
seguridad, sin fingir que todo funciona.)

**Antes de la demo real:** reintentar el chat; si el aviso de permisos de 2.3 se resuelve
(asignando el rol correcto al managed identity del Search service sobre el model deployment), es
probable que el chat funcione.

---

### 2.6 — Evaluación de calidad (Evaluations)

**Objetivo de la sección:** mostrar que Foundry permite medir calidad de respuesta de forma
sistemática, no solo "probar a ojo".

**Navegación:** Agents → `assurance-orchestrator` → pestaña **Evaluation**.

**Qué mostrar en pantalla:** estado actual — "No evaluations found" (aún no se ha corrido una
evaluación sobre este agente en Caldova).

**Captura:** `screenshots/15-evaluation-no-results.png`

**Mensaje de valor para el cliente:** *"Este tab es donde ejecutarías evaluaciones automatizadas de
groundedness, relevancia y seguridad (red-teaming) antes de promover un agente a producción. Hoy no
hay corridas en este tenant de demo, pero es el mismo flujo que verían en un entorno real — en
nuestro entorno propio lo mostramos ejecutado completo con resultados reales."* (Referencia opcional
al entorno archivado si el cliente pide ver un ejemplo de evaluación ya corrida:
`archived/invoice-audit-foundry-env/deliverables/`.)

---

## CAPÍTULO 3 — Seguridad y gobierno de agentes de IA

### 3.1 — Identidad de agente como superficie de gobierno

**Objetivo de la sección:** conectar el Capítulo 2 con el 3 — la identidad de Entra ID del agente
(vista en 2.2) es lo que Defender for Cloud usa para rastrear riesgo.

**Navegación:** (reutilizar) Agents → `invoice-analyst` → Details.

**Captura:** `screenshots/14-entra-agent-identity.png` (misma captura de 2.2, reutilizada aquí como
puente narrativo).

**Mensaje de valor para el cliente:** *"Recuerden esta identidad — es la misma que vamos a ver en el
grafo de ataque de Defender for Cloud en un momento."*

---

### 3.2 — Hallazgos de Defender for Cloud (Recommendations)

**Objetivo de la sección:** mostrar que Defender for Cloud ya está monitoreando activamente los
recursos de IA del tenant, con hallazgos reales.

**Navegación:** `portal.azure.com` (sesión Caldova) → **Microsoft Defender for Cloud** →
**Recommendations**.

**Qué mostrar en pantalla:** lista de recomendaciones activas — en este tenant: **3 High + 246
Medium**, varias con etiquetas de factor de riesgo **"Lateral Movement"** y **"Critical Resource"**.

**Captura:** `screenshots/09-defender-recommendations-caldova.png`

**Mensaje de valor para el cliente:** *"Defender for Cloud no solo te dice 'esto está mal
configurado' — te dice el *impacto*: si ese recurso mal configurado puede ser usado para moverse
lateralmente hacia un recurso crítico."*

---

### 3.3 — El hallazgo específico: Foundry + red

**Objetivo de la sección:** profundizar en el hallazgo relevante a IA — "Microsoft Foundry resources
should restrict network access", sobre el recurso Search `search-o556j2kgukjty`.

**Navegación:** Recommendations → clic en el hallazgo → **Affected resources** → recurso
`search-o556j2kgukjty`.

**Captura:** `screenshots/10-defender-recommendation-detail.png`

**Mensaje de valor para el cliente:** *"Este es el mismo servicio de Azure AI Search que vimos
alimentando el Knowledge Base del agente en el Capítulo 2. Defender for Cloud lo está marcando
porque tiene acceso de red amplio — y vamos a ver exactamente a qué otro recurso ese acceso lo
conecta."*

---

### 3.4 — El mapa de relaciones (Attack Path / Graph): la pieza central

**Objetivo de la sección:** la demostración más fuerte de seguridad — visualizar en un grafo cómo un
recurso de IA se conecta, vía identidad administrada, a un recurso con datos sensibles.

**Navegación:** dentro del detalle de la recomendación → pestaña **Graph**.

**Qué mostrar en pantalla:** el grafo real poblado:

```
search-o556j2kgukjty  →  Managed Identity (d823da64-c86c-4884...)  →  sto556j2kgukjty
   (Search service,           (System-assigned identity)              (Storage Account,
    "Entry point")                                                     marcado con ícono
                                                                         de corona = "Target"
                                                                         / recurso crítico)
```

**Captura:** `screenshots/11-defender-graph-tab.png` y, expandido,
`screenshots/12-defender-graph-expanded.png`

**Factores de riesgo mostrados en el nodo:** "Lateral Movement", "Lateral Movement With Sensitive
Data", "Exposure to the Internet".

**Mensaje de valor para el cliente:** *"Este es el corazón de la demo de seguridad. No es una lista
de configuraciones — es un **grafo de ataque real**: un atacante que comprometa el servicio de
búsqueda (el 'entry point', expuesto a internet) puede pivotar usando su identidad administrada
hacia el Storage Account que contiene los contratos de proveedores — y Defender for Cloud ya lo sabe
y lo marca como 'Target' con ícono de recurso crítico, antes de que ocurra."*

---

### 3.5 — Clasificación de datos sensibles

**Objetivo de la sección:** mostrar que Defender for Cloud no solo ve la topología de red — también
clasifica el **contenido** como sensible.

**Navegación:** Defender for Cloud → **Data and AI security**.

**Qué mostrar en pantalla:** panel "Sensitive resources (1)" señalando el Storage Account
`sto556j2kgukjty` como clasificado con datos sensibles por el escáner de Defender.

**Captura:** `screenshots/13-data-ai-security-sensitive.png`

**Mensaje de valor para el cliente:** *"Defender no asume que todo storage es sensible por
default — lo escanea y lo clasifica. Es este cruce (identidad + red + clasificación de datos) lo
que hace que el hallazgo del Graph tenga 'Lateral Movement With Sensitive Data', y no solo 'Lateral
Movement'."*

---

### 3.6 — Cierre: de la detección a la acción de gobierno

**Objetivo de la sección:** cerrar el capítulo mostrando que esto no se queda en un dashboard —
existe un camino claro hacia remediación/contención.

**Navegación:** desde el hallazgo (3.3) o desde el recurso afectado → acciones recomendadas
disponibles (ej. restringir acceso de red del Search service, revisar permisos del managed
identity, o — si se quiere mostrar contención activa de un agente comprometido — Entra ID → Agent
ID registry → acción de "Restrict App Execution" sobre la identidad del agente).

**Mensaje de valor para el cliente:** *"El flujo completo es: Foundry construye y opera el agente
(Capítulo 2) → Defender for Cloud lo vigila continuamente y traza su blast radius real (Capítulo 3)
→ el equipo de seguridad tiene una acción concreta de contención, sin tener que adivinar qué otros
recursos están en riesgo."*

---

## Resumen ejecutivo para cierre de demo

| Capítulo | Lo que vieron | Por qué importa |
|---|---|---|
| 2.1–2.2 | Catálogo multi-agente + identidad Entra real | No es un prompt suelto, es una arquitectura gobernable |
| 2.3 | Grounding real sobre Search + Blob Storage | Respuestas basadas en evidencia, no alucinadas |
| 2.4 | Traces de ejecución | Auditable, no es caja negra |
| 2.5 | Intento de chat en vivo (+ caveat honesto) | Transparencia: mostramos también fricciones reales |
| 2.6 | Evaluación de calidad | Framework de calidad antes de producción |
| 3.2–3.4 | Hallazgo + grafo de ataque real (Search→Identity→Storage) | Seguridad proactiva, no reactiva |
| 3.5 | Clasificación de datos sensibles | El riesgo se mide con el dato real en juego |
| 3.6 | Camino a remediación/contención | De la detección a la acción |

---

*Guion construido sobre navegación real en el tenant `Caldova50800867.onmicrosoft.com`, 26-oct.
Capturas en `deliverables/screenshots/`. Para el detalle técnico de por qué el entorno propio
(`invoice-audit-foundry2`) no pudo replicar el Capítulo 3 completo, ver
[`archived/invoice-audit-foundry-env/README-ARCHIVED.md`](../archived/invoice-audit-foundry-env/README-ARCHIVED.md).*
