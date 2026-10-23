# Invoice Audit Agent — Demo de Foundry (Capítulo 2: Build, Observe & Tune)

Scripts automatizados y repetibles para desplegar y eliminar el ambiente completo
de la demo "Invoice Audit Agent" en Microsoft Foundry — usados para mostrar el
ciclo de vida de un agente de IA (construir, fundamentar, observar y ajustar)
con un caso de uso real: auditoría de facturas de staffing contra un contrato
y un registro de aprobaciones de horas extra.

No necesitas recordar los pasos manuales ni volver a pedir ayuda cada vez —
este repo es la fuente de verdad para repetir el deploy N veces.

## Qué construye `deploy.sh`

| Recurso | Propósito |
|---|---|
| Resource group | Contenedor único — permite borrar todo con un solo comando |
| Foundry account + project (`Microsoft.CognitiveServices`, kind `AIServices`) | El proyecto de Microsoft Foundry |
| 3 model deployments | Modelo del agente, modelo de la knowledge base, modelo de embeddings |
| Storage account + contenedor blob | Aloja los 4 documentos de conocimiento (contrato, rate card, 2 facturas) versionados en `knowledge-docs/` |
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
    ├── Guion-Invoice-Audit-Agent-Capitulo2.docx   # Guion de navegación para la demo
    └── Invoice-Audit-Agent-Resumen.pptx            # Presentación de resumen ejecutivo
```

## Costos

Todos los recursos usan SKUs de bajo costo o pay-as-you-go (Search Serverless,
Storage Standard_LRS, App Insights pay-per-GB). El consumo real depende de
cuántas preguntas le hagas al agente. Como referencia, una build completa +
3 preguntas de prueba costó ~US$0.30–0.50 en consumo de modelo. **Siempre
corre `teardown.sh` al terminar una demo** para evitar cargos innecesarios
entre una presentación y la siguiente.
