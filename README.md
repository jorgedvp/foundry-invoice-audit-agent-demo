# Invoice Audit Agent — Demo de Foundry (Capítulos 2 y 3: Build/Observe/Tune + Seguridad)

> ## 🤖 Instrucciones para el agente de IA (léeme primero)
>
> Si el usuario te pide "despliega la demo de invoice audit", "levanta el
> ambiente de Foundry para la demo", "haz el deploy de este repo", o algo
> equivalente, **sigue estos pasos sin pedir aclaraciones adicionales**:
>
> 1. Clona o ubica este repo localmente.
> 2. Si no existe `config.env`, créalo copiando `config.env.example` tal cual
>    (los valores por defecto ya son correctos para el tenant/suscripción
>    documentados ahí — no inventes ni cambies nombres de recursos salvo que
>    el usuario lo pida explícitamente).
> 3. Corre `./scripts/deploy.sh config.env`. Esto tarda 20–30 minutos
>    (ver tabla de tiempos abajo) y es idempotente — es seguro re-ejecutarlo
>    si falla a mitad de camino.
> 4. **Un solo paso queda manual y requiere el portal** (ver sección
>    "Qué construye `deploy.sh`" abajo): crear el Evaluator custom y correr
>    la evaluación. Dile al usuario que ese paso falta y sigue el
>    [guion de navegación](deliverables/Guion-Invoice-Audit-Agent-Capitulo2-con-imagenes.docx),
>    sección "Sección 5 — Tune". No intentes automatizarlo por REST — ya se
>    intentó y esa función del portal no tiene API pública estable.
> 5. Valida el deploy enviando al menos una pregunta de prueba al agente
>    (el script ya lo hace automáticamente si `SEED_SAMPLE_TRAFFIC=true`).
>    No declares éxito sin confirmar que el agente respondió HTTP 200 con
>    contenido coherente.
> 6. Cuando el usuario pida terminar/limpiar la demo, corre
>    `./scripts/teardown.sh config.env --yes` — es un solo comando, no borres
>    recursos uno por uno.
>
> **El Capítulo 3 (seguridad) NO requiere un ambiente ni tenant separado.**
> Reutiliza el mismo agente/recursos del Capítulo 2 para mostrar gobierno e
> identidad de agentes (Entra ID) y postura de seguridad (Defender for Cloud).
> Ver sección "Capítulo 3 — Seguridad" abajo antes de navegar esa parte del
> guion, y **nunca deshabilites el acceso de red pública real** del recurso
> Foundry en vivo — rompería el agente que el usuario necesita seguir usando.
> La acción de contención real y segura de ejecutar en esta demo compartida es
> "asignar owner + due date" sobre la recomendación de Defender, no aplicar el
> Quick Fix de remediación.
>
> **No reinventes la arquitectura.** Este repo ya resolvió, a base de prueba
> y error contra el tenant real, varios problemas no obvios (ver sección
> "Notas de implementación / troubleshooting" al final). Si `deploy.sh` falla
> con un error nuevo, agrégalo a esa sección después de resolverlo, no lo
> dejes sin documentar.

Scripts automatizados y repetibles para desplegar y eliminar el ambiente completo
de la demo "Invoice Audit Agent" en Microsoft Foundry — usados para mostrar el
ciclo de vida de un agente de IA (construir, fundamentar, observar y ajustar)
con un caso de uso real: auditoría de facturas de staffing contra un contrato
y un registro de aprobaciones de horas extra. El mismo ambiente también cubre
el gobierno y la seguridad de ese agente (identidad en Entra ID, postura de
seguridad en Defender for Cloud) — ver "Capítulo 3 — Seguridad" más abajo.

No necesitas recordar los pasos manuales ni volver a pedir ayuda cada vez —
este repo es la fuente de verdad para repetir el deploy N veces.

## Qué construye `deploy.sh`

| Recurso | Propósito |
|---|---|
| Resource group | Contenedor único — permite borrar todo con un solo comando |
| Foundry account + project (`Microsoft.CognitiveServices`, kind `AIServices`) | El proyecto de Microsoft Foundry |
| 3 model deployments | Modelo del agente, modelo de la knowledge base, modelo de embeddings |
| Knowledge source (tipo File, subida directa) | Aloja los 4 documentos de conocimiento (contrato, rate card, 2 facturas) versionados en `knowledge-docs/` — sin necesidad de storage account |
| Azure AI Search (serverless) | Motor de indexación/recuperación detrás de Foundry IQ |
| Knowledge source + Knowledge base | Conectan los documentos al agente vía Foundry IQ |
| Conexión de proyecto (MCP) | Permite al agente invocar la knowledge base como herramienta |
| Application Insights + conexión | Habilita Traces y Monitor |
| Asignaciones de rol (RBAC) | Permisos entre Search ↔ Foundry ↔ App Insights ↔ Storage |
| Agente (`invoice-audit-agent`) | Con instrucciones + knowledge base conectada |
| 3 ejecuciones de prueba (opcional) | Pobla Traces/Monitor con datos reales antes de la demo |

**Un paso queda manual** (~5 minutos, documentado en la guía de navegación):
crear el Evaluator custom "Contract-Policy-Evidence Compliance" y correr la
evaluación. Ese paso depende de la generación automática de rúbricas por IA,
una función de portal que todavía no expone una API REST pública estable.

## Requisitos previos

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) instalado y autenticado (`az login`)
- Permisos de **Owner** o **User Access Administrator** en la suscripción (para las asignaciones de rol)
- `curl`, `python3` (para parsear algunas respuestas JSON)
- Cuota disponible de Azure OpenAI (modelos GlobalStandard) en la región elegida

## Uso

```bash
git clone https://github.com/jorgedvp/foundry-invoice-audit-agent-demo.git
cd foundry-invoice-audit-agent-demo
cp config.env.example config.env
# Edita config.env: subscripción, tenant, región, nombres de modelos si tu
# catálogo de Foundry usa nombres distintos (gpt-4o/gpt-4o-mini por defecto).

./scripts/deploy.sh config.env
```

Al finalizar, el script imprime el endpoint del proyecto y la URL del portal.
Abre `ai.azure.com`, selecciona el proyecto, y sigue el
[guion de navegación](deliverables/Guion-Invoice-Audit-Agent-Capitulo2.docx)
para la demo — esa guía es solo para **navegar y mostrar funcionalidades
dentro del portal**, no para configurar nada (eso ya lo hizo `deploy.sh`).

### Volver a desplegar (misma demo, ambiente limpio)

El script es idempotente: si vuelves a correrlo contra el mismo `config.env`,
detecta lo que ya existe y solo crea lo que falta. Para una repetición 100%
limpia, corre `teardown.sh` primero.

### Eliminar todo al terminar la demo

```bash
./scripts/teardown.sh config.env
```

Pide confirmación escribiendo el nombre del resource group. Para scripts/CI
sin interacción:

```bash
./scripts/teardown.sh config.env --yes
```

Esto elimina el resource group completo (`az group delete`) — todos los
recursos facturables desaparecen con un solo comando, sin dejar nada corriendo
entre demos.

## Tiempo estimado

| Escenario | Tiempo |
|---|---|
| Deploy desde cero (incluye propagación de RBAC) | 20–30 min |
| Teardown | 2–5 min (se ejecuta en segundo plano) |

El cuello de botella no es crear recursos — es la propagación de permisos
RBAC entre Azure AI Search, el recurso Foundry y Application Insights. El
script reintenta automáticamente cada paso que depende de permisos recién
asignados (hasta 10 minutos por paso) en vez de fallar de inmediato.

## Estructura del repo

```
.
├── config.env.example          # Plantilla de configuración (copiar a config.env)
├── knowledge-docs/              # Los 4 documentos que el agente audita (versionados)
├── scripts/
│   ├── deploy.sh                 # Despliega todo el ambiente
│   ├── teardown.sh               # Elimina todo el ambiente (1 comando)
│   └── lib/common.sh             # Helpers compartidos (logging, reintentos, RBAC)
└── deliverables/
    ├── Guion-Invoice-Audit-Agent-Capitulo2.docx                # Guion original (sin imágenes)
    ├── Guion-Invoice-Audit-Agent-Capitulo2-con-imagenes.docx   # Guion unificado Cap. 2 + 3, con capturas reales
    ├── Invoice-Audit-Agent-Resumen.pptx                        # Presentación de resumen ejecutivo
    ├── screenshots/                                            # Capturas del Capítulo 2 (Build/Observe/Tune)
    └── screenshots-cap3/                                       # Capturas del Capítulo 3 (Seguridad/Entra ID/Defender)
```

## Costos

Todos los recursos usan SKUs de bajo costo o pay-as-you-go (Search Serverless,
App Insights pay-per-GB). El consumo real depende de cuántas preguntas le
hagas al agente. Como referencia, una build completa + 3 preguntas de prueba
costó ~US$0.30–0.50 en consumo de modelo. **Siempre corre `teardown.sh` al
terminar una demo** para evitar cargos innecesarios entre una presentación y
la siguiente.

## Capítulo 3 — Seguridad (identidad de agentes y gobierno)

El mismo ambiente desplegado para el Capítulo 2 sirve, sin pasos de deploy
adicionales, para mostrar gobierno y seguridad de agentes de IA en producción.
No es una demo aparte ni requiere otro tenant — es el mismo
`invoice-audit-agent` visto desde Entra ID y Microsoft Defender for Cloud.

**Qué es scriptable (ya automatizado):**
- El plan "AI" (Standard) de Defender for Cloud se activa automáticamente al
  desplegar el Capítulo 2 en una suscripción nueva (trial de 30 días). Para
  habilitarlo manualmente en otra suscripción:
  `az security pricing create --name AI --tier Standard`.
- Verificar planes activos: `az security pricing list -o table`.

**Qué es solo-portal (no tiene API pública estable para automatizar la
navegación, pero sí para consultar datos si se requiere scripting futuro):**
- Microsoft Entra Agent ID (`entra.microsoft.com` → Entra ID → Agents): registro
  de identidad de los agentes del tenant. Disponible de forma nativa, sin
  activación.
- Microsoft Defender for Cloud (`portal.azure.com` → Microsoft Defender for
  Cloud): Inventory, Recommendations, Attack path analysis, Cloud Security
  Explorer.

**Secciones del guion (ver
[`deliverables/Guion-Invoice-Audit-Agent-Capitulo2-con-imagenes.docx`](deliverables/Guion-Invoice-Audit-Agent-Capitulo2-con-imagenes.docx),
capítulo 3 al final del documento):**
1. Identidad de agentes en Entra ID (Overview + detalle de una identidad).
2. Hallazgo real de seguridad en Defender for Cloud (recomendaciones
   "Unhealthy" detectadas automáticamente sobre el recurso Foundry real).
3. Mapa de relaciones / Attack path analysis (honesto: puede mostrar "No
   attack paths found" si el plan Defender se activó hace menos de 24-48h —
   el grafo de relaciones tarda en indexar completamente).
4. Contención y auditoría: asignar owner + due date sobre la recomendación
   (equivalente real y seguro al "Restrict App Execution + comentario de
   auditoría" del guion original de Caldova).

**⚠️ Regla de seguridad para quien ejecute esta demo:** nunca apliques la
remediación completa (deshabilitar acceso de red pública, botón "Fix" /
Quick Fix) sobre el recurso Foundry en vivo si el ambiente sigue en uso para
el Capítulo 2 — rompería el Playground, la API, y las Evaluations. La acción
de contención segura y reversible de esta demo es "asignar owner + due date",
no la remediación de red.

## Notas de implementación / troubleshooting

Estos son problemas reales encontrados al validar `deploy.sh` contra el
tenant real — ya están resueltos en el script, pero quedan documentados aquí
por si reaparecen (p. ej. si Azure cambia una API) o si extiendes el script:

1. **`semanticSearch` debe ser `"standard"`, no el valor por defecto `"free"`.**
   Un Azure AI Search serverless creado sin este flag falla al crear
   cualquier Knowledge Source con un error 500 genérico
   (`"Failed to create or update Knowledge Source" / "An error has occurred."`)
   sin ningún detalle útil. Se descubrió comparando, campo por campo, un
   servicio creado manualmente que sí funcionaba contra uno recién creado por
   script. `deploy.sh` ya fuerza este valor tanto en creación como en
   actualización de un servicio existente.

2. **Azure AI Search serverless requiere la API version `2026-09-01-Preview`**
   en este tenant — versiones anteriores (`2025-05-01`, `2025-02-01-Preview`,
   etc.) devuelven `InvalidSkuName` para el SKU `serverless`.

3. **Storage Account con acceso público bloqueado por política del tenant.**
   Algunas suscripciones fuerzan `publicNetworkAccess: Disabled` en cuentas de
   storage nuevas, lo que rompe la subida de blobs vía CLI/REST. Se evitó el
   problema de raíz: el script ya no usa Storage Account en absoluto — sube
   los documentos directamente al Knowledge Source tipo `file` vía la API de
   datos de Azure AI Search (`POST .../knowledgesources('name')/files`).

4. **`az cognitiveservices account create --identity-type SystemAssigned` no
   existe** en versiones recientes del CLI — el flag correcto es solo
   `--assign-identity` (sin especificar el tipo).

5. **Resource providers no registrados en una suscripción nueva** (en
   particular `Microsoft.Storage`) causan `SubscriptionNotFound` en llamadas
   que no tienen nada que ver con storage. El script ahora registra
   automáticamente todos los providers necesarios antes de crear nada.

6. **Cognitive Services (cuentas Foundry) usan soft-delete.** Si corres
   `teardown.sh` y vuelves a desplegar con el mismo `FOUNDRY_ACCOUNT_NAME`,
   Azure devuelve `FlagMustBeSetForRestore` en vez de crear una cuenta nueva.
   Tanto `deploy.sh` como `teardown.sh` detectan y purgan automáticamente
   cuentas soft-deleted con el mismo nombre.

7. **La API de Responses cambió el nombre del campo del agente.** La
   documentación y el ejemplo original usaban `"agent": {"type": "agent_reference", ...}`,
   pero el tenant actual exige `"agent_reference": {"type": "agent_reference", ...}`
   como campo raíz — `"agent"` ahora devuelve `invalid_payload` (deprecado).

8. **La conexión MCP y el agente deben usar el mismo nombre como
   `server_label` y `project_connection_id`.** Si no coinciden exactamente
   con el nombre real de la conexión creada (`PROJECT_CONNECTION_NAME` en
   `config.env`), el agente se crea pero no logra invocar la knowledge base.

9. **El registro de agentes de Foundry sobrevive al borrado del resource
   group y al purge de la cuenta.** Se detectó que, al recrear el ambiente
   completo (borrar `rg-invoice-audit-demo` + purgar la cuenta Foundry
   soft-deleted + volver a desplegar con los mismos nombres), el agente
   `invoice-audit-agent` ya existía con la configuración **vieja** (apuntando
   al Search/modelo del despliegue anterior) y cada intento de creación fallaba
   con `409 Conflict`. El retry-loop de `deploy.sh` reportaba esto como
   `"not ready yet"` indefinidamente hasta agotar el timeout de 600s, aunque el
   agente nunca se iba a actualizar solo reintentando el mismo POST. `deploy.sh`
   ahora borra defensivamente (`DELETE /agents/{name}`, ignorando 404) cualquier
   agente preexistente con el mismo nombre justo antes de crearlo, para que la
   creación sea realmente idempotente.

10. **La propagación de RBAC para la llamada de *retrieval* del MCP
    (`knowledge_base_retrieve`) puede tardar varios minutos más que la
    creación del agente en sí.** El `POST /agents` puede devolver éxito
    inmediatamente, pero el primer intento real de invocar la knowledge base
    desde el agente puede devolver `HTTP 403 Forbidden` ("Access denied when
    connecting to the MCP server...") durante varios minutos aunque los roles
    (`Search Index Data Reader` / `Search Service Contributor` en el servicio
    de Search para la identidad administrada del proyecto, y
    `Cognitive Services User` en la cuenta Foundry para la identidad del
    servicio de Search) ya estén asignados y confirmados vía
    `az role assignment list`. Es exclusivamente un retraso de propagación en
    el plano de datos de Search, no un problema de configuración. `deploy.sh`
    ahora reintenta automáticamente la primera pregunta de muestra (no solo la
    creación del agente) hasta que realmente devuelva `HTTP 200`, usando los
    mismos `RBAC_WAIT_TIMEOUT_SECONDS` / `RBAC_POLL_INTERVAL_SECONDS` de
    `config.env`. Ocasionalmente también se observó un `403` intermitente y
    aislado en una sola pregunta después de que otras ya habían funcionado —
    reintentar una vez más resuelve esto (flakiness del servicio preview, no
    un problema de RBAC real).

11. **NUNCA purgues y re-crees la cuenta Foundry con el mismo nombre si el
    portal "nuevo" de Foundry (ai.azure.com/nextgen) ya la indexó.** La
    documentación oficial de Microsoft lo advierte explícitamente
    ("Don't purge the Foundry account resource. A purge makes recovery
    involve additional steps and considerations not documented here") y en
    este tenant el síntoma fue muy concreto: tras purgar y re-desplegar con
    el mismo `FOUNDRY_ACCOUNT_NAME`, **la API de datos del agente funcionaba
    perfecto** (`HTTP 200`, respuestas correctas con citas), pero el portal
    nuevo (`ai.azure.com/nextgen`) mostraba permanentemente
    `"Agent not found"` / `"Error loading your agents. Project not found"`
    en las pestañas Agents/Build/Traces — un registro interno del portal
    quedó apuntando al proyecto purgado y nunca se resincronizó, ni siquiera
    esperando 20+ minutos. La única solución confirmada fue dejar de reusar
    el nombre purgado: desplegar la cuenta Foundry con un **nombre nuevo**
    (p. ej. `invoice-audit-foundry2`) resolvió el problema al instante en el
    portal nuevo, reutilizando sin problema el mismo Azure AI Search y
    Application Insights ya existentes. **Efecto secundario importante:**
    como el Search Service y sus Knowledge Source/Knowledge Base quedan
    ligados al *endpoint* de la cuenta Foundry con la que se crearon, y
    Azure AI Search rechaza cambiar ese endpoint en un recurso existente
    (`"The embedding endpoint cannot be changed"`), `deploy.sh` ahora borra
    defensivamente (ignorando 404) cualquier Knowledge Base/Knowledge Source
    preexistente con esos nombres antes de recrearlos — igual que ya hacía
    con el agente — para que un cambio de `FOUNDRY_ACCOUNT_NAME` (por este
    mismo motivo, o por cualquier redeploy futuro) sea siempre idempotente.
    `config.env.example` usa `invoice-audit-foundry2` como nombre por
    defecto precisamente por esta lección.

