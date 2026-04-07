--
-- Knowledge System Migration (Phase 1 + Phase 2)
--
-- Phase 1: Enriched Memory — neue Spalten auf memory_long + erweiterte Suchfunktionen
-- Phase 2: Knowledge Graph — kg_entities + kg_relations + Graph-Traversal
--
-- Idempotent: kann mehrfach ausgeführt werden (IF NOT EXISTS / CREATE OR REPLACE)
-- Einzige Ausnahme: DROP FUNCTION für search_memory/search_memory_keyword
-- (Return-Type-Änderung erfordert DROP vor CREATE)
--

-- ============================================================
-- PHASE 1: Enriched Memory
-- ============================================================

-- Neue Spalten auf memory_long
ALTER TABLE public.memory_long ADD COLUMN IF NOT EXISTS tags text[] DEFAULT '{}';
ALTER TABLE public.memory_long ADD COLUMN IF NOT EXISTS entity_name text;
ALTER TABLE public.memory_long ADD COLUMN IF NOT EXISTS source text;

-- Indexes für die neuen Spalten
CREATE INDEX IF NOT EXISTS idx_memory_long_entity_name
  ON public.memory_long (entity_name)
  WHERE entity_name IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_memory_long_tags
  ON public.memory_long USING gin (tags)
  WHERE tags != '{}';

-- Erweiterte Suchfunktion: search_memory
-- DROP nötig weil sich der Return-Type ändert (3 neue Spalten)
DROP FUNCTION IF EXISTS public.search_memory(public.vector, double precision, integer, text);
DROP FUNCTION IF EXISTS public.search_memory(public.vector, double precision, integer, text, text, text[]);

CREATE FUNCTION public.search_memory(
  query_embedding public.vector,
  match_threshold double precision DEFAULT 0.7,
  match_count integer DEFAULT 5,
  filter_category text DEFAULT NULL,
  filter_entity text DEFAULT NULL,
  filter_tags text[] DEFAULT NULL
) RETURNS TABLE(
  id integer,
  content text,
  category text,
  importance integer,
  similarity double precision,
  metadata jsonb,
  created_at timestamp with time zone,
  tags text[],
  entity_name text,
  source text
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ml.id,
    ml.content,
    ml.category,
    ml.importance,
    1 - (ml.embedding <=> query_embedding) as similarity,
    ml.metadata,
    ml.created_at,
    ml.tags,
    ml.entity_name,
    ml.source
  FROM memory_long ml
  WHERE
    (filter_category IS NULL OR ml.category = filter_category)
    AND (filter_entity IS NULL OR ml.entity_name ILIKE filter_entity)
    AND (filter_tags IS NULL OR ml.tags @> filter_tags)
    AND 1 - (ml.embedding <=> query_embedding) > match_threshold
    AND (ml.expires_at IS NULL OR ml.expires_at > now())
  ORDER BY ml.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

ALTER FUNCTION public.search_memory(public.vector, double precision, integer, text, text, text[]) OWNER TO postgres;

GRANT ALL ON FUNCTION public.search_memory(public.vector, double precision, integer, text, text, text[]) TO anon;
GRANT ALL ON FUNCTION public.search_memory(public.vector, double precision, integer, text, text, text[]) TO authenticated;
GRANT ALL ON FUNCTION public.search_memory(public.vector, double precision, integer, text, text, text[]) TO service_role;

-- Erweiterte Suchfunktion: search_memory_keyword
DROP FUNCTION IF EXISTS public.search_memory_keyword(text, integer);
DROP FUNCTION IF EXISTS public.search_memory_keyword(text, integer, text, text[]);

CREATE FUNCTION public.search_memory_keyword(
  search_query text,
  match_count integer DEFAULT 5,
  filter_entity text DEFAULT NULL,
  filter_tags text[] DEFAULT NULL
) RETURNS TABLE(
  id integer,
  content text,
  category text,
  importance integer,
  metadata jsonb,
  created_at timestamp with time zone,
  tags text[],
  entity_name text,
  source text
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ml.id,
    ml.content,
    ml.category,
    ml.importance,
    ml.metadata,
    ml.created_at,
    ml.tags,
    ml.entity_name,
    ml.source
  FROM memory_long ml
  WHERE
    ml.content ILIKE '%' || search_query || '%'
    AND (filter_entity IS NULL OR ml.entity_name ILIKE filter_entity)
    AND (filter_tags IS NULL OR ml.tags @> filter_tags)
    AND (ml.expires_at IS NULL OR ml.expires_at > now())
  ORDER BY ml.importance DESC, ml.created_at DESC
  LIMIT match_count;
END;
$$;

ALTER FUNCTION public.search_memory_keyword(text, integer, text, text[]) OWNER TO postgres;

GRANT ALL ON FUNCTION public.search_memory_keyword(text, integer, text, text[]) TO anon;
GRANT ALL ON FUNCTION public.search_memory_keyword(text, integer, text, text[]) TO authenticated;
GRANT ALL ON FUNCTION public.search_memory_keyword(text, integer, text, text[]) TO service_role;


-- ============================================================
-- PHASE 2: Knowledge Graph
-- ============================================================

-- Entitäten-Tabelle
CREATE TABLE IF NOT EXISTS public.kg_entities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  entity_type TEXT,
  summary TEXT,
  metadata JSONB DEFAULT '{}',
  embedding public.vector(1536),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kg_entities OWNER TO postgres;

-- Beziehungen-Tabelle
CREATE TABLE IF NOT EXISTS public.kg_relations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id UUID REFERENCES public.kg_entities(id) ON DELETE CASCADE,
  target_id UUID REFERENCES public.kg_entities(id) ON DELETE CASCADE,
  relation_type TEXT NOT NULL,
  weight FLOAT DEFAULT 1.0,
  metadata JSONB DEFAULT '{}',
  valid_from TIMESTAMPTZ DEFAULT now(),
  valid_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kg_relations OWNER TO postgres;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_kg_entities_type ON public.kg_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_kg_entities_name ON public.kg_entities(name);
CREATE INDEX IF NOT EXISTS idx_kg_relations_source ON public.kg_relations(source_id);
CREATE INDEX IF NOT EXISTS idx_kg_relations_target ON public.kg_relations(target_id);
CREATE INDEX IF NOT EXISTS idx_kg_entities_embedding ON public.kg_entities USING hnsw (embedding public.vector_cosine_ops);

-- Grants
GRANT ALL ON TABLE public.kg_entities TO anon;
GRANT ALL ON TABLE public.kg_entities TO authenticated;
GRANT ALL ON TABLE public.kg_entities TO service_role;

GRANT ALL ON TABLE public.kg_relations TO anon;
GRANT ALL ON TABLE public.kg_relations TO authenticated;
GRANT ALL ON TABLE public.kg_relations TO service_role;

-- Semantische Entity-Suche
CREATE OR REPLACE FUNCTION public.search_entities(
  query_embedding public.vector DEFAULT NULL,
  search_name text DEFAULT NULL,
  filter_type text DEFAULT NULL,
  match_threshold double precision DEFAULT 0.7,
  match_count integer DEFAULT 10
) RETURNS TABLE(
  id UUID,
  name TEXT,
  entity_type TEXT,
  summary TEXT,
  metadata JSONB,
  similarity double precision,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.name,
    e.entity_type,
    e.summary,
    e.metadata,
    CASE WHEN query_embedding IS NOT NULL AND e.embedding IS NOT NULL
      THEN 1 - (e.embedding <=> query_embedding)
      ELSE 0.0
    END AS similarity,
    e.created_at
  FROM public.kg_entities e
  WHERE
    (filter_type IS NULL OR e.entity_type = filter_type)
    AND (search_name IS NULL OR e.name ILIKE '%' || search_name || '%')
    AND (
      query_embedding IS NULL
      OR e.embedding IS NULL
      OR 1 - (e.embedding <=> query_embedding) > match_threshold
    )
  ORDER BY
    CASE WHEN query_embedding IS NOT NULL AND e.embedding IS NOT NULL
      THEN e.embedding <=> query_embedding
      ELSE 0
    END
  LIMIT match_count;
END;
$$;

ALTER FUNCTION public.search_entities(public.vector, text, text, double precision, integer) OWNER TO postgres;

GRANT ALL ON FUNCTION public.search_entities(public.vector, text, text, double precision, integer) TO anon;
GRANT ALL ON FUNCTION public.search_entities(public.vector, text, text, double precision, integer) TO authenticated;
GRANT ALL ON FUNCTION public.search_entities(public.vector, text, text, double precision, integer) TO service_role;

-- Graph-Traversal (rekursive CTE, Multi-Hop)
CREATE OR REPLACE FUNCTION public.search_entity_graph(
  start_id UUID,
  max_depth integer DEFAULT 2
) RETURNS TABLE(
  entity_id UUID,
  name TEXT,
  entity_type TEXT,
  summary TEXT,
  depth integer,
  relation_type TEXT,
  relation_direction TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE graph AS (
    -- Hop 1: ausgehende Beziehungen
    SELECT r.target_id AS eid, 1 AS d, r.relation_type AS rtype, 'outgoing'::text AS dir
    FROM public.kg_relations r
    WHERE r.source_id = start_id
      AND (r.valid_until IS NULL OR r.valid_until > now())
    UNION
    -- Hop 1: eingehende Beziehungen
    SELECT r.source_id, 1, r.relation_type, 'incoming'::text
    FROM public.kg_relations r
    WHERE r.target_id = start_id
      AND (r.valid_until IS NULL OR r.valid_until > now())
    UNION ALL
    -- Hop 2+: rekursiv (ausgehend)
    SELECT r.target_id, g.d + 1, r.relation_type, 'outgoing'::text
    FROM public.kg_relations r
    JOIN graph g ON r.source_id = g.eid
    WHERE g.d < max_depth
      AND (r.valid_until IS NULL OR r.valid_until > now())
    UNION ALL
    -- Hop 2+: rekursiv (eingehend)
    SELECT r.source_id, g.d + 1, r.relation_type, 'incoming'::text
    FROM public.kg_relations r
    JOIN graph g ON r.target_id = g.eid
    WHERE g.d < max_depth
      AND (r.valid_until IS NULL OR r.valid_until > now())
  )
  SELECT DISTINCT ON (g.eid)
    g.eid AS entity_id,
    e.name,
    e.entity_type,
    e.summary,
    g.d AS depth,
    g.rtype AS relation_type,
    g.dir AS relation_direction
  FROM graph g
  JOIN public.kg_entities e ON e.id = g.eid
  ORDER BY g.eid, g.d;
END;
$$;

ALTER FUNCTION public.search_entity_graph(UUID, integer) OWNER TO postgres;

GRANT ALL ON FUNCTION public.search_entity_graph(UUID, integer) TO anon;
GRANT ALL ON FUNCTION public.search_entity_graph(UUID, integer) TO authenticated;
GRANT ALL ON FUNCTION public.search_entity_graph(UUID, integer) TO service_role;
