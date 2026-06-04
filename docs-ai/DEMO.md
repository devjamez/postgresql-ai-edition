# Demo — real output

All of this runs inside PostgreSQL, locally, with **no API key** (Ollama + `nomic-embed-text` + `llama3.1:8b`). Reproduce with `examples/demo.sql` and `examples/filtered_search.sql`.

## 1. Semantic search

```sql
WITH q AS (SELECT ai.embed('notebook para desarrollo de IA') AS v)
SELECT nombre, round(ai.similarity(embedding, (SELECT v FROM q))::numeric, 3) AS score
FROM productos ORDER BY embedding <=> (SELECT v FROM q) LIMIT 3;
```
```
      nombre      | score
------------------+-------
 MacBook Pro M3   | 0.836
 Dell XPS 15      | 0.780
 Teclado mecánico | 0.643
```

## 2. RAG (grounded in your tables)

```sql
SELECT ai.rag('¿Qué producto me conviene para entrenar modelos de IA?',
              'productos', 'descripcion', 'embedding', 3);
```
```
Laptop para desarrolladores con buena GPU (el primer punto del contexto)
es adecuada para entrenar modelos de IA.
```

## 3. Agent with memory

```sql
SELECT ai.create_agent('asesor', 'Sos un asesor de compras de tecnología. Respondé corto y directo.');
SELECT ai.call_agent('asesor', 'Hola, busco una laptop para programar');
SELECT ai.call_agent('asesor', '¿Y para jugar también sirve?');
```
Turn 2 remembers turn 1 (note "también" — it continues the laptop conversation):
```
turn 1 → ...te recomiendo procesador Intel Core i5/i7, 16 GB RAM, SSD... (Dell XPS, HP Envy, Lenovo ThinkPad)
turn 2 → Si también vas a jugar, considerá tarjeta gráfica dedicada...
         (Dell G3/G5, HP Omen, Lenovo Legion con NVIDIA)
```

## 4. Filtered ANN — relational filter fused with vector similarity

```sql
-- no filter: top-3 by similarity (a 'software' row sneaks in)
SELECT content, round(distance::numeric,3) FROM ai.filtered_search(
  'entrenar modelos de inteligencia artificial','articulos','titulo','embedding','true',3);
```
```
 GPU para entrenamiento de redes neuronales profundas | 0.374
 Servidor con muchas GPUs para IA                     | 0.427
 Editor de texto para programar                       | 0.447   ← software
```
```sql
-- fused with a relational filter: only 'hardware', still top-3 by distance
SELECT content, round(distance::numeric,3) FROM ai.filtered_search(
  'entrenar modelos de inteligencia artificial','articulos','titulo','embedding',
  'categoria = ''hardware''',3);
```
```
 GPU para entrenamiento de redes neuronales profundas | 0.374
 Servidor con muchas GPUs para IA                     | 0.427
 Notebook liviana para ofimática                      | 0.512   ← software excluded,
                                                                  over-fetch reached the 3rd hardware row
```

The filtered query **drops the closer software row** and reaches further to return 3 `hardware` rows — adaptive over-fetch via pgvector's iterative scan, no engine fork.
