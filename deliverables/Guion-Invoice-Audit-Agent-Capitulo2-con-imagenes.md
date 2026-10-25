> **Nota:** esta es la versión Markdown de la guía — fuente canónica a partir de ahora para
> ediciones rápidas (se renderiza con imágenes directo en GitHub). El `.docx` con el mismo
> contenido sigue disponible para imprimir o compartir fuera de GitHub, pero si encuentras
> algo que corregir, repórtalo sobre este archivo primero.

**Capítulos 2 y 3 — Build, Observe & Tune + Seguridad**

Guion de navegación — Invoice Audit Agent (ciclo de vida completo + gobierno de seguridad)

*Ambiente desplegado en tenant propio (ME-MngEnvMCAP947629) · Microsoft Foundry*

*📸 Versión con capturas de pantalla reales — generada navegando el ambiente ya desplegado (cuenta Foundry invoice-audit-foundry2, recreada limpia tras un purge de la cuenta original) el 23-24 oct 2026. Úsala para apoyarte visualmente mientras sigues la guía original; el contenido y el orden de las secciones son idénticos.*

> **Ambiente de la demo**
> Proyecto: invoice-audit-demo · Recurso Foundry: invoice-audit-foundry2 · Resource group: rg-invoice-audit-demo · Región: East US 2 · Modelo del agente: gpt-4o (OpenAI, Global Standard) — nota: el ambiente manual original usaba gpt-6-astra; el redeploy scripted usa gpt-4o por disponibilidad de cuota · Knowledge base: invoice-audit-knowledge (Foundry IQ sobre Azure AI Search).

# Tiempo estimado de despliegue

Antes de presentar esta demo frente a un cliente, planifica el despliegue del ambiente con anticipación. No lo dejes para el mismo día — especialmente por los tiempos de propagación de permisos (RBAC).

| Paso | Tiempo estimado | Notas |
|---|---|---|
| Crear proyecto de Foundry + deployment del modelo | 5–8 min | Incluye creación del resource group y selección de región con cupo disponible. |
| Crear recurso Azure AI Search + conexión Foundry IQ | 5–8 min | Puede requerir probar otra región si la elegida está sin capacidad. |
| Preparar y subir documentos a la Knowledge Base | 5 min | Preparar los archivos (contrato, registro de aprobaciones, facturas) toma más tiempo que la subida en sí. |
| Conceder permisos RBAC entre Search ↔ Foundry ↔ App Insights | 15–20 min | El paso más lento: cada asignación de rol puede tardar de 1 a 10 minutos en propagar antes de que el agente pueda consultar la knowledge base o las trazas. |
| Crear el agente, instrucciones y conectar Knowledge | 5 min |  |
| Conectar Application Insights (Traces/Monitor) | 5 min | Requiere su propia asignación de rol — ver fila de RBAC arriba. |
| Generar 2-3 ejecuciones reales en el Playground | 5 min | Necesario para poblar Traces y Monitor con datos reales antes de la demo. |
| Crear el Evaluator custom + correr la evaluación | 5–8 min | Incluye la generación automática de la rúbrica por IA (~1 min de espera). |
| TOTAL (primera vez, de cero) | 45–60 min | Con permisos RBAC ya propagados de una build anterior, se puede repetir en ~20–25 min. |

> **⚠️ Lección aprendida (validada en vivo)**
> El cuello de botella real no es crear los recursos — es la propagación de los permisos RBAC entre Azure AI Search, el recurso Foundry y Application Insights. Si una consulta del agente falla con error 403 ("Access denied") inmediatamente después de asignar un rol, espera 1-2 minutos adicionales y reintenta antes de asumir que algo está mal configurado.

*Recomendación: arma el ambiente completo al menos un día antes de la demo, verifica que las 2-3 ejecuciones de prueba y la evaluación corran sin errores, y luego solo reutiliza ese mismo ambiente el día de la presentación (sin tener que reconstruirlo).*

# Objetivo de esta sección de la demo

Mostrar el ciclo de vida completo de un agente de IA en Microsoft Foundry — construir, fundamentar (ground), observar y ajustar — usando un caso de uso realista: un agente que audita facturas de un proveedor de staffing (ServicePro) contra un contrato (MSA) y un registro de aprobaciones de horas extra.

Mensaje central para el cliente: un agente de producción no es una caja negra. Cada respuesta se puede rastrear (Traces), cada ejecución se puede medir en costo y uso (Monitor), y la calidad se puede certificar de forma sistemática y repetible (Evaluations) — sin salir del mismo portal donde se construyó.

# Escenario de negocio (para contar antes de navegar)

Meridian Manufacturing contrata personal de planta a través de ServicePro Staffing Solutions bajo un contrato marco (MSA-2025-0417). El contrato exige que cualquier hora extra facturada tenga una autorización previa por escrito, registrada por sitio y mes (Sección 3.2). Sin un agente, el equipo de Procurement debe cruzar manualmente cada línea de factura contra el contrato y el registro de aprobaciones — un proceso lento y propenso a errores.

El Invoice Audit Agent automatiza esa auditoría: lee la factura, el contrato y el registro de aprobaciones (todo vía Foundry IQ), identifica líneas de horas extra sin aprobación válida, calcula el monto no facturable, cita la cláusula exacta del contrato, y recomienda una disposición (Aprobar / Escalar / Necesita más información).

# Sección 1 — Build: construir el agente con grounding real

> **Objetivo de esta sección**
> Mostrar que un agente de producción se construye en minutos: modelo + instrucciones + conocimiento empresarial conectado — sin escribir código.

## Navegación

- Portal: Microsoft Foundry → portal.azure (ai.azure.com) → proyecto invoice-audit-demo
- URL directa (Playground del agente):
https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/agents/invoice-audit-agent/build?tid=e00660b6-957d-4851-a2b1-26d94d7527cd

**Qué mostrar en pantalla**

- Panel izquierdo: "Instructions" — lee en voz alta 2-3 líneas de las instrucciones del agente (rol: Invoice Audit Agent, tarea: auditar contra MSA + registro de aprobaciones).
- Panel izquierdo: "Knowledge" — muestra la knowledge base conectada: invoice-audit-knowledge → fuente servicepro-contract-and-invoices (4 documentos: contrato MSA, rate card/registro de aprobaciones, 2 facturas).
- Panel central: "Model" — gpt-4o, Global Standard deployment (en el ambiente manual original era gpt-6-astra; el redeploy scripted usa gpt-4o).
- Panel de chat: escribe en vivo la pregunta — "Please audit invoice INV-2026-08602 from ServicePro Staffing Solutions (Columbus, OH site, August 2026) against the MSA and the overtime pre-approval log. Flag any non-billable overtime and tell me the dollar amount at risk."
**Resultado esperado (ya verificado en el ambiente)**

**El agente responde: Disposición = Escalate (credit required). Monto no facturable = $8,342.25 (227 horas de OT de un trabajador sin referencia de aprobación). Cita exacta: MSA Sección 3.2(c) + la fila del registro de aprobaciones que confirma que no existe otra autorización para ese sitio/mes.**

![Captura 1](screenshots/01-build-playground.png)

*Captura 1 — Playground del agente: instrucciones, modelo (gpt-4o) y Knowledge conectada.*

![Captura 2](screenshots/02-build-chat-response.png)

*Captura 2 — Respuesta real del agente en vivo: hallazgo de $8,342.25 con citas numeradas a la knowledge base.*

**Mensaje de valor para el cliente**

*"Este agente no solo responde — cada afirmación está anclada a un documento real que ustedes controlan. No hay alucinación de cifras: el monto y la cláusula vienen directamente de su contrato y su registro de aprobaciones, indexados vía Foundry IQ."*

# Sección 2 — Grounding: Foundry IQ / Knowledge

> **Objetivo de esta sección**
> Mostrar de dónde viene el conocimiento del agente: una base de conocimiento empresarial real, no datos del modelo.

## Navegación

https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/knowledge?tid=e00660b6-957d-4851-a2b1-26d94d7527cd

**Qué mostrar en pantalla**

- Pestaña "Knowledge bases" → invoice-audit-knowledge.
- Abre la fuente servicepro-contract-and-invoices → muestra los 4 archivos cargados (contrato MSA, rate card, 2 facturas) con su estado "Active".
- Explica brevemente: esto corre sobre Azure AI Search (Foundry IQ), con un modelo (gpt-4o en este ambiente; era gpt-5.4 en el manual original) orquestando la recuperación — no es una simple búsqueda por palabra clave, es recuperación agentic con razonamiento.

*Nota: el panel lateral "Knowledge" del portal nuevo usa un flujo de conexión por API Key independiente y puede mostrarse vacío aunque la Knowledge Base ya esté conectada al agente vía Managed Identity/MCP (como se ve en la Captura 1 de la Sección 1, donde "invoice-audit-knowledge" aparece conectada y respondiendo). Si el cliente pregunta, aclara que es el mismo recurso, solo visualizado desde dos paneles distintos del portal.*

**Mensaje de valor para el cliente**

*"Pueden conectar SharePoint, Blob Storage, bases SQL, o simplemente subir archivos como hicimos aquí. El agente decide qué documento consultar según la pregunta — esto es lo que llamamos retrieval agentic."*

**Cómo ver los 4 documentos reales (ruta confirmada en vivo)**

El portal de Foundry no permite navegar los documentos de una Knowledge Base ya conectada — hay que ir al recurso de **Azure AI Search** directamente en el Portal de Azure:

1. Ve a `portal.azure.com` (no `ai.azure.com`).
2. Busca el recurso: **`invoice-audit-search`**.
3. En el menú izquierdo, bajo **"Search management"**: clic en **"Indexes"**.
4. Verás el índice **`servicepro-contract-and-invoices-index`** con **Document count: 5** (4 documentos originales + 1 registro adicional generado por el proceso de indexación).
5. Haz clic en el nombre del índice → pestaña **"Search explorer"** (seleccionada por defecto) → clic en el botón **"Search"** (con el cuadro de búsqueda vacío, para traer todos los documentos).
6. Verás el JSON completo de cada documento indexado: `snippet` (el texto real extraído, p. ej. una cláusula del contrato sobre reglas de horas extra), `snippet_vector` (el embedding numérico usado para la búsqueda semántica), y metadatos.

![Captura 7](screenshots/07-search-service-indexes.png)

*Captura 7 — Azure AI Search: el índice `servicepro-contract-and-invoices-index` con 5 documentos, 242.66 KB de almacenamiento total.*

![Captura 8](screenshots/08-search-explorer-documents.png)

*Captura 8 — Search Explorer: contenido real de un documento indexado — el `snippet` de texto extraído del contrato y su vector de embedding.*

**Qué es Azure AI Search y cómo explicárselo al cliente**

> Azure AI Search es el motor de búsqueda e indexación que hace posible que el agente "lea" documentos reales en vez de inventar respuestas. No es una base de datos tradicional — además de guardar el texto, genera un **embedding** (una representación numérica del significado del texto) para cada fragmento de documento, lo que le permite al agente encontrar la información relevante aunque la pregunta no use las palabras exactas del documento ("búsqueda semántica", no solo por palabra clave).
>
> En este caso, es el motor detrás de **Foundry IQ** (la capa de "Knowledge Bases" que ya vimos en el agente): Foundry IQ orquesta la recuperación con razonamiento, y Azure AI Search es quien realmente almacena, indexa y devuelve los fragmentos de los 4 documentos (el contrato MSA, el rate card/registro de aprobaciones, y las 2 facturas).
>
> Mensaje para el cliente: *"Esto es lo mismo que usan miles de aplicaciones empresariales en Azure para dar 'memoria documental' a un agente de IA — sus contratos, políticas o manuales se indexan una sola vez, y el agente los consulta en tiempo real cada vez que responde. Ustedes pueden ver exactamente qué fragmento de texto usó el agente para fundamentar cada respuesta — no hay caja negra."*

# Sección 3 — Observe: Traces (trazabilidad)

> **Objetivo de esta sección**
> Mostrar que cada respuesta del agente es auditable paso a paso: qué modelo se llamó, qué herramienta se invocó, cuánto costó, cuánto tardó.

## Navegación

https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/agents/invoice-audit-agent/traces?tid=e00660b6-957d-4851-a2b1-26d94d7527cd

**Qué mostrar en pantalla**

- Tabla de Traces: selecciona la ejecución más reciente (la de la factura INV-2026-08602).
- Columnas visibles: Status (Completed), Duration (segundos), Tokens In/Out, Estimated cost (USD).
- Abre el detalle de una traza → muestra el árbol de pasos: la llamada al modelo, la llamada a la knowledge base vía MCP (Model Context Protocol), y la respuesta final con las citas numeradas.

![Captura 3](screenshots/03-traces-list.png)

*Captura 3 — Lista de Traces: 4 ejecuciones reales, todas "Completed", con duración, tokens y costo estimado.*

![Captura 4](screenshots/04-trace-detail.png)

*Captura 4 — Detalle de una traza: árbol de pasos (Invoke Agent → Execute Tool knowledge_base_retrieve → Chat gpt-4o).*

**Mensaje de valor para el cliente**

*"Si un auditor o un gerente de cumplimiento pregunta '¿de dónde salió este número?', aquí está la respuesta exacta: el documento, el fragmento, y el razonamiento del modelo — en segundos, no en una investigación manual."*

# Sección 4 — Observe: Monitor (operación continua)

> **Objetivo de esta sección**
> Mostrar la vista operacional agregada: costo, consumo de tokens, y salud del agente en producción a lo largo del tiempo.

## Navegación

https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/agents/invoice-audit-agent/monitor/overview?tid=e00660b6-957d-4851-a2b1-26d94d7527cd

**Qué mostrar en pantalla**

- Tarjeta "Operational metrics": costo estimado acumulado (~$0.32 en este ambiente de demo) y uso total de tokens (~25.3K).
- Tarjeta "Evaluations": punto de entrada para configurar evaluaciones recurrentes y alertas automáticas de calidad.
- Menciona (sin necesidad de abrir) las tarjetas de "Scheduled red teaming" — pruebas automáticas de seguridad — disponibles en el mismo panel.

![Captura 5](screenshots/05-monitor.png)

*Captura 5 — Monitor: costo acumulado ($0.13), uso de tokens (13.6K) y métricas operacionales del agente en este ambiente.*

**Mensaje de valor para el cliente**

*"Esto es gobierno de costos de IA en tiempo real — el mismo principio de FinOps que ya aplican a su infraestructura de Azure, pero para consumo de modelos de lenguaje y agentes."*

## Monitor → "Configure": evaluaciones recurrentes y red teaming automático (preconfigurado)

> **Objetivo de esta sección**
> Mostrar que el monitoreo de un agente en producción no se limita a costo y tokens: Foundry permite automatizar la certificación continua de calidad/seguridad (evaluaciones recurrentes) y pruebas adversariales programadas (red teaming), sin que nadie tenga que ejecutarlas manualmente cada semana.

**Dónde está esto en el portal — ¡cuidado! hay DOS botones "Configure" en esta pantalla**

En Monitor → Overview hay **dos tarjetas distintas que cada una tiene su propio botón "Configure"**: la tarjeta **"Evaluations"** (columna del medio) y la tarjeta **"Scheduled red teaming run issues"** (fila de abajo, a la izquierda). A simple vista parecen llevar a cosas distintas — **no es así: ambos botones abren exactamente el mismo diálogo "Monitor settings"**, solo que son dos puntos de entrada distintos a la misma pantalla. Confirmado en vivo haciendo clic en cada uno por separado.

Ese diálogo "Monitor settings" tiene una lista de 5 opciones en el panel izquierdo:

| Opción (panel izquierdo) | Qué controla |
|---|---|
| App. Insights resource | Conexión a Application Insights (ya "Connected" desde el Capítulo 2 — Traces/Monitor). |
| Insights (Preview) | Paneles analíticos adicionales sobre el comportamiento del agente. |
| Recurring evaluations | Evaluaciones de calidad/seguridad que se ejecutan solas en una cadencia fija. |
| Scheduled red teaming runs | Pruebas de seguridad adversariales en una cadencia fija. |
| Evaluation Alerts | Notificaciones cuando una métrica de evaluación cae bajo un umbral. |

*Nota de nomenclatura confirmada en vivo: la tarjeta "Scheduled evaluations" que aparece en la vista general de Monitor y la opción "Recurring evaluations" de este diálogo son la misma funcionalidad — Foundry la muestra con dos nombres en dos lugares distintos de la misma pantalla.*

### Evaluaciones recurrentes — "weekly-quality-monitor" (ya configurada y activa)

**Qué mostrar en pantalla**

Build → Evaluations → pestaña **"Recurring configs" (Preview)**: aparece `weekly-quality-monitor`, Frecuencia = Scheduled, 0 corridas todavía (se ejecutará sola según el ciclo configurado).

![Captura 9](screenshots/09-recurring-evaluation-created.png)

*Captura 9 — Evaluación recurrente "weekly-quality-monitor" ya creada y activa (pestaña Recurring configs).*

**Configuración real aplicada** (para que quede documentado qué se decidió y por qué):

- **Target:** invoice-audit-agent (siempre evalúa la versión activa/desplegada más reciente — no una versión fija).
- **Scope:** Individual turns (correcto para un agente de preguntas-y-respuestas tipo RAG, no una conversación multi-turno).
- **Frecuencia:** Recurring → Scheduled → cada **1 semana**, sobre **Live traffic** (tráfico real de producción, no un dataset estático), con muestreo **Random** de hasta **100 trazas por corrida**.
- **Criterios (evaluadores):** 4 evaluadores de seguridad recomendados por defecto — Violence, Sexual, Self-harm, Hate and unfairness — más **Output quality** (que añadimos nosotros: cubre fluency, coherence, intent resolution, task adherence, groundedness y task completion — las dimensiones de calidad más relevantes para un agente de auditoría de facturas).
- **Juez:** modelo gpt-4o (Global Standard).

**Qué NO quedó configurado en esta pasada** (transparencia para no sobre-prometer en la demo): el wizard de creación no incluye un campo de "umbral de alerta %" dentro del mismo flujo — esa pieza vive en el toggle separado **"Evaluation Alerts"** del diálogo "Monitor settings", y normalmente se configura una vez que la evaluación recurrente ya generó al menos una corrida con resultados. No se activó en esta sesión; queda como posible paso siguiente si se quiere mostrar la alerta real funcionando.

**Mensaje de valor para el cliente**

*"Esto es lo que ustedes ya hacen con monitoreo de infraestructura — alertas automáticas cuando algo se desvía — aplicado a la calidad del agente. No se necesita que alguien se acuerde de correr una evaluación cada semana: ya quedó programada, corre sola contra tráfico real, y en el futuro puede avisar automáticamente si la calidad cae bajo un umbral."*

### Red teaming — una corrida real ejecutada en este ambiente

**Qué mostrar en pantalla**

Build → Evaluations → pestaña **"Red team" (Preview)**: a diferencia de las evaluaciones recurrentes, aquí **no existe una opción de programar una cadencia** dentro del asistente — cada red team es una corrida puntual bajo demanda. Confirmado en vivo: el toggle "Scheduled red teaming runs" existe en Monitor settings, pero el asistente de creación de un red team ("Create red teaming run") no tiene ningún paso de frecuencia/cadencia — solo Target → Run configuration → Review prohibited actions → Review → Submit.

![Captura 10](screenshots/10-redteam-tab.png)

*Captura 10 — Pestaña "Red team" (Preview) dentro de Evaluations, antes de crear la primera corrida.*

![Captura 11](screenshots/11-redteam-create-wizard.png)

*Captura 11 — Paso 1 del asistente: elegir el objetivo (Agent) a atacar.*

![Captura 12](screenshots/12-redteam-run-configuration.png)

*Captura 12 — Paso 2 "Run configuration": categorías de riesgo (taxonomía "Standard" — 9 categorías: fuga de datos sensibles, acciones prohibidas, violencia, atributos sin fundamento, adherencia a la tarea, contenido sexual, autolesión, odio/discriminación y vulnerabilidades de código), cantidad de consultas semilla por categoría, y estrategias de ataque a aplicar.*

Dos categorías de riesgo ("Prohibited actions" y "Task adherence", marcadas con \*) exigen describir las herramientas del agente antes de continuar — Foundry usa esa descripción para generar ataques específicos al contexto real del agente, no genéricos:

> *Tool description (mcp): "MCP tool that queries the servicepro-contract-and-invoices knowledge base (MSA contract, rate card, overtime approvals, and vendor invoices) to answer invoice audit questions."*

![Captura 13](screenshots/13-redteam-prohibited-actions.png)

*Captura 13 — Paso 3 "Review prohibited actions": taxonomía de acciones prohibidas auto-generada (genérica de plataforma, no específica de este agente) que hay que revisar y confirmar antes de lanzar el escaneo — ej. "Changing a Password", "Bypassing Browser Security Warnings", "Transacting in Regulated Goods".*

![Captura 14](screenshots/14-redteam-taxonomy-review.png)

*Captura 14 — Detalle del modal de revisión de taxonomía de acciones prohibidas.*

![Captura 15](screenshots/15-redteam-review-final.png)

*Captura 15 — Paso 4 "Review": resumen final antes de enviar — objetivo, 9 categorías de riesgo, estrategia de ataque "AsciiArt", y la descripción de la herramienta MCP.*

Se envió como **"invoice-audit-security-scan"** y quedó corriendo en vivo contra el agente real.

**Mensaje de valor para el cliente**

*"Esto no es un checklist de seguridad genérico — es un agente de IA especializado que ataca a su propio agente de producción con las mismas técnicas que usaría un adversario real (inyección de prompts, jailbreaks codificados, intentos de que el agente ejecute acciones fuera de su propósito), usando el contexto específico de sus herramientas y datos conectados."*

### Programar el red teaming para que corra solo — descubrimiento clave

**Corrección importante respecto a lo que pensábamos al investigar esto:** el asistente **"Create red teaming run"** (el que se muestra arriba) en efecto NO tiene un paso de frecuencia — cada clic en "Create" ahí genera una corrida puntual. **Pero eso no significa que el red teaming no se pueda programar.** La programación vive en otro lugar: dentro del mismo diálogo **"Monitor settings"** (ver sección anterior), seleccionando **"Scheduled red teaming runs"** en el panel izquierdo.

Ese panel no abre un asistente nuevo — es un simple interruptor que **reutiliza un red team y una corrida que ya existan** (en nuestro caso, el `invoice-audit-security-scan` recién creado) y les aplica una cadencia:

![Captura 16](screenshots/16-scheduled-redteam-configured.png)

*Captura 16 — "Scheduled red teaming runs" activado: Red team = invoice-audit-security-scan, Red teaming run = redteam-run-zm4cg1yq, Schedule = Monthly.*

**Configuración real aplicada:**

- **Red team:** invoice-audit-security-scan (el mismo que se creó y documentó arriba).
- **Red teaming run:** redteam-run-zm4cg1yq (la corrida puntual ya ejecutada — sirve de plantilla para las corridas futuras).
- **Schedule:** Monthly (opciones disponibles: Hourly, Daily, Weekly, Monthly).

Tras enviar ("Submit"), "Scheduled red teaming runs" pasa de "Disabled" a **"Enabled"** en el panel izquierdo — confirmado reabriendo el diálogo:

![Captura 19](screenshots/19-scheduled-redteam-saved-confirmed.png)

*Captura 19 — Confirmación: "Scheduled red teaming runs" ahora en estado "Enabled" con la configuración guardada.*

**Mensaje de valor para el cliente (versión corregida y más fuerte)**

*"Y esto no se queda en una sola prueba de seguridad — igual que programamos la evaluación de calidad semanal, podemos programar que este mismo ataque adversarial se repita automáticamente cada mes, usando como plantilla el escaneo que ya corrimos. Es decir: ni la calidad ni la seguridad del agente dependen de que alguien se acuerde de probarlas — las dos quedan corriendo solas."*

# Sección 5 — Tune: Evaluator y mejora continua

> **Objetivo de esta sección**
> Mostrar que la calidad del agente no se mide 'a ojo' — existe una rúbrica medible, repetible y auditable que certifica si el agente cumple su propósito.

## Navegación — Catálogo de evaluadores

https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/evaluations/catalog/contract-policy-evidence-compliance/1?tid=e00660b6-957d-4851-a2b1-26d94d7527cd

**Qué mostrar en pantalla (evaluador)**

- Evaluador custom: "Contract-Policy-Evidence Compliance" (tipo Rubric, auto-generado por IA a partir de una instrucción en lenguaje natural).
- Dimensiones con peso: line_item_audit_correctness (peso 9) — ¿el agente asignó correctamente la disposición de facturación según la evidencia? y evidence_grounding_and_citation (peso 6) — ¿cada hallazgo cita una cláusula y una fila del registro real?

*Nota importante: como este ambiente fue recreado limpio (nueva cuenta Foundry), el evaluador custom "Contract-Policy-Evidence Compliance" TODAVÍA NO EXISTE aquí — debe crearse manualmente siguiendo el paso documentado en el repo (~5 min) antes de poder mostrar esta sección. La siguiente captura muestra el estado de partida real (pestaña Evaluation vacía) desde el que debes arrancar ese paso manual.*

![Captura 6](screenshots/06-evaluation-tab-empty.png)

*Captura 6 — Estado de partida: pestaña Evaluation del agente antes de crear el evaluador custom ("No evaluations found").*

## Navegación — Resultados de la evaluación

https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/evaluations/eval_b47d2fd7fb654844b4e252f5b60761e6?tid=e00660b6-957d-4851-a2b1-26d94d7527cd

*Nota: este ID de evaluación (eval_b47d2fd7...) corresponde al ambiente manual original y ya no existe aquí. Una vez que crees el evaluador y corras una nueva evaluación en este ambiente, copia la URL real desde la barra de direcciones y reemplaza esta referencia antes de la demo.*

**Qué mostrar en pantalla (resultados)**

- Evaluación "invoice-audit-evaluation-run-1" ejecutada sobre 3 trazas reales (Application Insights traces) — no datos sintéticos.
- Score global: 67% (28/42) combinando 7 evaluadores (seguridad + calidad + el evaluador custom).
- Score del evaluador custom "contract-policy-evidence-compliance": 100% (3/3) — las 3 respuestas del agente citaron evidencia real y asignaron la disposición correcta.
- Abre el detalle de una fila para mostrar el razonamiento del juez (modelo gpt-5.4) explicando por qué aprobó o rechazó cada dimensión.
**Mensaje de valor para el cliente**

*"Esto no es un checklist manual una vez al trimestre. Pueden programar esta evaluación para correr de forma recurrente, sobre tráfico real de producción, y recibir una alerta si la calidad cae por debajo de un umbral — antes de que el cliente o el auditor lo note."*

# Cierre sugerido

"Recorrimos el ciclo completo: construimos un agente con conocimiento empresarial real (Build), verificamos que cada respuesta es trazable y auditable (Observe vía Traces y Monitor), y certificamos su calidad con una rúbrica medible y repetible (Tune vía Evaluations). Todo dentro de la misma plataforma — Microsoft Foundry — sin herramientas adicionales, sin exportar datos a otro sistema."

## Resumen de URLs de navegación

- Playground / Build: https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/agents/invoice-audit-agent/build?tid=e00660b6-957d-4851-a2b1-26d94d7527cd
- Traces: https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/agents/invoice-audit-agent/traces?tid=e00660b6-957d-4851-a2b1-26d94d7527cd
- Monitor: https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/agents/invoice-audit-agent/monitor/overview?tid=e00660b6-957d-4851-a2b1-26d94d7527cd
- Knowledge: https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/knowledge?tid=e00660b6-957d-4851-a2b1-26d94d7527cd
- Evaluator catalog: https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/evaluations/catalog/contract-policy-evidence-compliance/1?tid=e00660b6-957d-4851-a2b1-26d94d7527cd
- Resultados de evaluación: https://ai.azure.com/nextgen/r/3eUZlgMRTK6RlV-UO9QbxQ,rg-invoice-audit-demo,,invoice-audit-foundry2,invoice-audit-demo/build/evaluations/eval_b47d2fd7fb654844b4e252f5b60761e6?tid=e00660b6-957d-4851-a2b1-26d94d7527cd

# Capítulo 3 — Seguridad: identidad de agentes y gobierno

**Objetivo de esta sección**

Mostrar cómo gobernar y asegurar agentes de IA en producción: visibilidad de identidad (Microsoft Entra Agent ID), detección automática de riesgos reales (Microsoft Defender for Cloud), y una acción de contención auditable — todo sobre el MISMO agente que construimos en el Capítulo 2 (invoice-audit-agent, cuenta invoice-audit-foundry2). No es un ambiente aparte: es la misma demo, vista desde la perspectiva de seguridad y gobierno.

**Prerrequisito (ya habilitado en este tenant, sin pasos adicionales)**

- Microsoft Defender for Cloud — plan "AI" (Standard) ya está activo en esta suscripción (trial de 30 días). Se puede habilitar en cualquier tenant con: az security pricing create --name AI --tier Standard.
- Microsoft Entra Agent ID (registro de identidades de agente) está disponible de forma nativa en Entra ID — no requiere activación ni licencia adicional más allá de Entra ID estándar.

## Sección 1 — Identidad de agentes (Microsoft Entra Agent ID)

**Navegación**

- Portal: entra.microsoft.com → Entra ID → Agents
https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/overview

**Qué mostrar en pantalla**

- Panel "Overview": 8 identidades de agente detectadas en el tenant, todas asociadas a nuestro ambiente (invoice-audit-foundry / invoice-audit-foundry2), con sus "Agent blueprints" (plantillas padre) listados a la derecha.

![Captura 7](screenshots-cap3/01-entra-agents-overview.png)

*Captura 1 — Entra ID Agents Overview: 8 identidades de agente activas, blueprints recientes mostrando nuestro propio ambiente.*

- Clic en "View all agent identities" → lista completa con Status "Active" y fecha de creación (10/23/26, el mismo día del deploy del Capítulo 2).
- Clic en una identidad específica (invoice-audit-foundry2/projects/invoice-audit-demo) → detalle de la Enterprise Application asociada: Application ID, Object ID, Conditional Access, Permissions, Sign-in logs.

![Captura 8](screenshots-cap3/02-entra-agent-identity-detail.png)

*Captura 2 — Detalle de la identidad del agente en Entra ID: propiedades, Application ID/Object ID, y opciones de gobierno (Conditional Access, Roles, Permissions).*

**Mensaje de valor para el cliente**

"Cada agente de IA que se crea en Foundry tiene una identidad gobernable en Entra ID — igual que cualquier aplicación empresarial. Pueden ver, auditar y aplicar Conditional Access sobre estas identidades, sin importar cuántos agentes desplieguen en su organización. No hay agentes 'fantasma' o fuera del radar de identidad."

## Sección 2 — Hallazgo real de seguridad (Microsoft Defender for Cloud)

**Navegación**

- Portal: portal.azure.com → Microsoft Defender for Cloud → Inventory → invoice-audit-foundry2
https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/25

**Qué mostrar en pantalla**

- 2 recomendaciones activas "Unhealthy" sobre nuestro propio recurso, detectadas automáticamente por Defender sin ninguna configuración manual: "Microsoft Foundry resources should use Azure Private Link" y "Microsoft Foundry resources should restrict network access".

![Captura 9](screenshots-cap3/03-defender-findings-before.png)

*Captura 3 — Resource health de invoice-audit-foundry2: 2 recomendaciones Unhealthy reales, detectadas automáticamente por Defender for Cloud.*

- Clic en "should restrict network access" → detalle completo: descripción, Attack Paths (0 por ahora), tácticas MITRE ATT&CK asociadas (Lateral Movement, Exploitation of Remote Services, Lateral Tool Transfer, Remote Services), y plan de remediación (Quick Fix automático + instrucciones manuales paso a paso).

![Captura 10](screenshots-cap3/04-defender-recommendation-detail.png)

*Captura 4 — Detalle de la recomendación: descripción, plan de remediación (Quick Fix), y tácticas MITRE ATT&CK que este hallazgo habilitaría si se combinara con otros.*

**Mensaje de valor para el cliente**

"Esto no es un recurso de ejemplo — es el agente real que construimos juntos en el Capítulo 2. Defender lo detectó automáticamente apenas se desplegó, sin que nadie lo configurara manualmente ni corriera un escaneo a propósito."

## Sección 3 — Mapa de relaciones / Attack Path Analysis

**Navegación**

- Portal: Microsoft Defender for Cloud → Attack path analysis
https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/AttackPaths

**Qué mostrar en pantalla**

- "No attack paths found" (0 total, 0 recursos afectados). Es un resultado honesto y esperado: los hallazgos actuales (Sección 2) son de riesgo Low y aún no se combinan entre sí en una cadena explotable completa — pero Defender los sigue rastreando de forma proactiva, antes de que escalen.

![Captura 11](screenshots-cap3/05-defender-graph-relationship-map.png)

*Captura 5 — Attack path analysis: sin rutas de ataque activas hoy. La pestaña "Graph" dentro de la recomendación individual también muestra "No relevant graph context found" por el mismo motivo (ver nota abajo).*

*Nota de timing: el plan Defender for AI se activó hace poco más de 24 horas en este tenant. El motor de grafo de relaciones (el que construye el mapa completo de blast radius, similar al escenario original de Caldova con OpenClaw → storage account "internalpayments") puede tardar hasta 24-48h en indexar todas las relaciones entre recursos tras activarse. Si repites esta demo varios días después del deploy inicial, es probable que el grafo ya muestre relaciones completas (p. ej. agente → Search → Knowledge Base) incluso sin un hallazgo crítico que las dispare.*

**Mensaje de valor para el cliente**

"Defender no solo lista problemas sueltos — intenta conectar los puntos para ver si un atacante podría encadenarlos en una ruta real de compromiso. Hoy no hay una ruta completa, que es exactamente la postura que queremos, pero seguimos viendo y corrigiendo cada pieza individual antes de que se convierta en una."

## Sección 4 — Contención y auditoría

**Navegación**

- Misma recomendación ("should restrict network access") → sección "Recommendation owner and set due date" → botón "Assign owner & set due date".
**Qué mostrar en pantalla**

- Antes: Status = "Unassigned", sin owner ni due date (ver Captura 3/4).
- Asignar: owner = admin@mngenvmcap947629.onmicrosoft.com, remediation timeframe = fecha por defecto (2 semanas).
- Después: Status cambia a "On time", con Recommendation owner y Due date (11/7/2026) visibles en la sección "Governance" — este es el equivalente real y auditable de "Restrict App Execution + comentario de auditoría" del guion original de Caldova.

![Captura 12](screenshots-cap3/06-defender-containment-after.png)

*Captura 6 — Después de la asignación: Status = "On time", Recommendation owner y Due date asignados en la sección Governance. Acción de contención real y auditable, sin romper la conectividad del agente.*

*⚠️ Nota importante de seguridad para quien ejecute esta demo: a propósito NO se deshabilitó el acceso de red pública real del recurso — eso rompería la conectividad del invoice-audit-agent (Playground, API, Evaluations) que se usa en el Capítulo 2 y que el usuario necesita seguir revisando. La acción de "asignar owner + due date" es el paso de gobierno/auditoría real y seguro de ejecutar en esta demo compartida. En un ambiente de producción real separado, el siguiente paso sería aplicar la remediación completa vía el botón "Fix" (Quick Fix) o manualmente — Networking → "Selected Networks and Private Endpoints" o "Disabled" — una vez validado que no interrumpe la operación.*

**Mensaje de valor para el cliente**

"La gobernanza de seguridad no es un evento único — es un ciclo: detectar, asignar dueño, fijar fecha, remediar, verificar. Aquí ven ese ciclo completo corriendo sobre su propio agente de producción, con trazabilidad total de quién es responsable y para cuándo."

# Cierre sugerido — Capítulo 3

"Recorrimos el otro lado de la moneda: no solo construimos y operamos un agente (Capítulo 2) — también lo gobernamos. Su identidad está registrada y es auditable en Entra ID. Su postura de seguridad se monitorea automáticamente en Defender for Cloud, con hallazgos reales, tácticas MITRE ATT&CK mapeadas, y una acción de contención con dueño y fecha — todo sin salir de las mismas herramientas de Microsoft que ya usan hoy, y sobre el mismo agente que acabamos de construir."

## Resumen de URLs de navegación — Capítulo 3

- Entra ID Agents (Overview): https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/overview
- Entra ID Agent identities (lista completa): https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/allAgentIds
- Defender for Cloud — Inventory: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/25
- Defender for Cloud — Data and AI security: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/AscInformationProtection
- Defender for Cloud — Attack path analysis: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/AttackPaths
- Defender for Cloud — Cloud Security Explorer: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/SecurityGraph