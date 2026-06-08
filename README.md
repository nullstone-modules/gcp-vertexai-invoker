# GCP Vertex AI Invoker

A least-privilege Nullstone capability that grants a workload's runtime identity exactly enough IAM to **call** Vertex AI models — and nothing else.

## Overview

The common path is to hand a workload `roles/aiplatform.user` so it can reach Vertex AI. 
That role also grants the ability to launch training jobs, deploy endpoints, and run batch prediction — capabilities an inference client never exercises, but that turns a compromised credential into a cost-bomb and an arbitrary-compute foothold.

This capability grants only the two permissions an inference workload actually uses (a LiteLLM proxy, an app calling Gemini / Claude / Kimi, an embedding service):

- `aiplatform.endpoints.predict` — model invocation. Covers `generateContent` / `streamGenerateContent` (Gemini), `rawPredict` / `streamRawPredict` (Claude, Kimi, and other partner/MaaS models), embeddings, and calls to self-deployed endpoints.
- `aiplatform.endpoints.computeTokens` — server-side token counting. Used by Gemini's `countTokens`; optional for Anthropic-only workloads, which count client-side.

It packages these into a project-scoped custom IAM role and binds that role to the target workload identity. The worst-case abuse of the resulting credential is bounded inference spend — which you cap further with Vertex quotas and application-layer budgets.

## What it deliberately does NOT grant

- Custom / hyperparameter-tuning jobs (`aiplatform.customJobs.*`)
- Endpoint creation or model deployment (`aiplatform.endpoints.create`, `aiplatform.models.upload`, `…deployModel`)
- Batch prediction jobs (`aiplatform.batchPredictionJobs.*`)
- Dataset, featurestore, and pipeline management
- Context-cache resource management (`aiplatform.cachedContents.*`)
- Any IAM or project mutation

This exclusion list is the product. The capability is a narrow edge between a workload and Vertex inference, not a general grant of "use Vertex."

## How it works

- Creates a project-level custom role (`vertexAiInvoker` by default) containing the two permissions above.
- Binds that role to the workload's runtime service account:
    - **As a capability attached to an app block**, it auto-discovers and binds the app's runtime service account (e.g., your LiteLLM service running on GKE via Workload Identity).
    - **Standalone**, you pass the target service account email explicitly.

IAM here is project-scoped and **not** region-specific. Which Vertex region/location a request targets is configured at the application layer (e.g., LiteLLM's `vertex_location`), not in this capability. Granting predict at the project level keeps the role stable across region changes.

## Prerequisites

- Vertex AI API (`aiplatform.googleapis.com`) enabled on the project.
- **Partner/MaaS models entitled in Model Garden.** Invoking Claude, Kimi, or other third-party models requires a one-time entitlement (accept commercial terms on the model card), which needs `roles/consumerprocurement.entitlementManager`. Entitlement is per-project and per-region.

> **This capability intentionally does not perform model entitlement.** Entitlement enables new paid third-party models and is a privileged, human-in-the-loop action. Keeping it out of an automated runtime grant is deliberate: the running workload should be able to *call* already-entitled models, never to *enable* new ones. Handle entitlement once through a separate admin path with the entitlement-manager role.

## Usage

Attach as a capability to the app that invokes Vertex (e.g., your LiteLLM proxy). When attached, the target identity is resolved automatically from the app block — no service account wiring required.

For standalone use, supply `project_id` and `target_service_account`.

## Inputs

| Name                     | Description                                                                                                           | Default               |
|--------------------------|-----------------------------------------------------------------------------------------------------------------------|-----------------------|
| `include_compute_tokens` | Include `aiplatform.endpoints.computeTokens`. Set `false` for Anthropic-only workloads that count tokens client-side. | `true`                |

## Security notes

The runtime credential is ambient — Workload Identity keeps a valid token in the pod continuously — and the workload it backs (an API gateway / model proxy) is typically the most exposed surface in the stack. Under `roles/aiplatform.user`, a stolen token can provision GPU/TPU capacity and run arbitrary containers via custom jobs. Under this role, it can only invoke models.

The tight scope also makes detection cheap: any non-predict Vertex action originating from this identity is an unambiguous anomaly, rather than something that blends into a broad role's legitimate traffic.

Pair with **Vertex quotas** (cap request volume) and **application-layer budgets** such as LiteLLM virtual-key spend limits (cap cost). IAM removes the dangerous categories of action; quotas and budgets bound the one category that remains.

For SOC2, this maps directly to least-privilege / access-control evidence: the custom role definition is the auditable artifact, and its permission set is minimal and explicit.

## Extending

If you enable additional Vertex features, grant additive permissions rather than widening back to `aiplatform.user`:

- **Batch prediction** → `aiplatform.batchPredictionJobs.*`
- **Gemini explicit context caching** (managing `CachedContent`) → `aiplatform.cachedContents.*`. Note: Anthropic prompt caching is an inline `cache_control` block inside the request payload and needs no extra permission.
- **Callback logging** to GCS / BigQuery → the relevant storage / BigQuery permissions, ideally scoped to a separate identity rather than folded in here.

Each missing permission surfaces as a precise `PERMISSION_DENIED` naming the exact permission, so you can grant only what's required.