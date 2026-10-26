# Guía de demo — Caldova (Capítulos 2 y 3: Build/Observe/Tune + Seguridad)

## Propósito de este repo

Este repositorio contiene la **guía de navegación para la demo en vivo**, construida a partir del **tenant de Caldova** (no de un ambiente propio). La guía cubre los mismos puntos narrativos que se querían mostrar originalmente:

- **Capítulo 2 — Build, Observe & Tune Agents**: construir, observar y ajustar un agente en Microsoft Foundry.
- **Capítulo 3 — Seguridad**: identidad de agentes (Microsoft Entra Agent ID), postura de seguridad (Microsoft Defender for Cloud), mapa real de relaciones/Attack Path, y contención.

La guía principal está en [`deliverables/Guion-Caldova-Demo.md`](deliverables/Guion-Caldova-Demo.md), con capturas de pantalla reales del tenant de Caldova en `deliverables/screenshots/`.

## Por qué el cambio de enfoque

Se intentó originalmente construir un ambiente propio desde cero (agente "Invoice Audit" en una suscripción sandbox de Microsoft) para tener control total sobre la demo. Ese trabajo está documentado y archivado en [`archived/invoice-audit-foundry-env/`](archived/invoice-audit-foundry-env/README-ARCHIVED.md) — incluye los scripts de despliegue, la guía original, y una explicación técnica detallada de por qué la sección del "mapa de relaciones / Attack Path" no se pudo completar ahí (un bloqueo real de gobernanza de la suscripción sandbox que no se puede exceptuar).

El tenant de Caldova ya tiene construido el escenario completo y funcionando (incluyendo el mapa de relaciones real: identidad → storage account con datos sensibles clasificados), por lo que la demo en vivo usa ese tenant directamente.

## Cómo usar este repo

1. Abre [`deliverables/Guion-Caldova-Demo.md`](deliverables/Guion-Caldova-Demo.md).
2. Sigue la guía sección por sección — cada una indica qué mostrar en pantalla, con una captura real de referencia y el mensaje de valor para el cliente.
3. Inicia sesión en el tenant de Caldova (`admin@caldova50800867.onmicrosoft.com`) antes de empezar.
