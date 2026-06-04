# PostgreSQL AI Edition — Knowledge Base (FASE 13)

The master index of the architecture documentation. Everything here is grounded in the shipped code; status is marked ✅ built / 🟡 partial / 📐 designed.

## Master architecture
- [MASTER-ARCHITECTURE.md](MASTER-ARCHITECTURE.md) — the capstone: vision, what shipped, and how it all fits.

## Decisions & RFCs
- [ADR-0001 — Extension vs. Fork](ADR-0001-extension-vs-fork.md)
- [RFC-0001 — V2 relational+vector plan fusion](RFC-0001-v2-plan-fusion.md)
- [RFC-0002 — Filtered HNSW (M2-recall) + partial-index recipe](RFC-0002-filtered-hnsw.md)

## Phases
- [FASE 1 — Anatomy of PostgreSQL 16](01-postgresql-anatomy.md) *(source-cited)*
- [FASE 2 — AI components, types, SQL surface](02-ai-components.md)
- [FASE 3 — Semantic SQL](03-semantic-sql.md)
- [FASE 4 — AI Planner](04-ai-planner.md)
- [FASE 5 — AI Storage Layer](05-ai-storage.md)
- [FASE 6 — AI Indexes](06-ai-indexes.md)
- [FASE 7 — AI Runtime](07-ai-runtime.md)
- [FASE 8 — RAG Engine](08-rag-engine.md)
- [FASE 9 — Agent Engine](09-agent-engine.md)
- [FASE 10 — AI Security](10-ai-security.md)
- [FASE 11 — Deployment & Cloud](11-ai-cloud.md)
- [FASE 12 — Roadmap (V1–V5)](12-roadmap.md)

## Operational / product
- [Demo — real output](DEMO.md)
- [Testing plan](TESTING.md)
- [Publishing plan](PUBLISHING.md)
- [Announcement drafts](ANNOUNCEMENT.md)
- [Original master prompt](00-master-prompt.md)

## How to read this
Start with [MASTER-ARCHITECTURE](MASTER-ARCHITECTURE.md) for the big picture, [FASE 1](01-postgresql-anatomy.md) for the PostgreSQL substrate, then the phase that matches your interest. The [main README](../README.md) is the quickstart and SQL reference.
