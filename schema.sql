-- schema.sql
-- Run once: psql -U jeeven -d stt_db -f schema.sql
-- Safe to re-run: all statements use IF NOT EXISTS / IF NOT EXISTS semantics

CREATE EXTENSION IF NOT EXISTS vector;

-- ── migrations: add missing columns to pre-existing tables ───────────────────
ALTER TABLE IF EXISTS recordings   ADD COLUMN IF NOT EXISTS device_id  TEXT;
ALTER TABLE IF EXISTS recordings   ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE IF EXISTS transcripts  ADD COLUMN IF NOT EXISTS device_id  TEXT;
ALTER TABLE IF EXISTS transcripts  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE IF EXISTS summaries    ADD COLUMN IF NOT EXISTS device_id  TEXT;
ALTER TABLE IF EXISTS summaries    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS device_id  TEXT;
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS task             TEXT NOT NULL DEFAULT '';
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS intent_type      TEXT NOT NULL DEFAULT 'general';
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS temporal_cue     TEXT;
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS raw_quote        TEXT;
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS semantic_score   NUMERIC(5,3);
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS temporal_score   NUMERIC(5,3);
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS cognitive_score  NUMERIC(5,3);
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS fused_confidence NUMERIC(5,3);
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS decision         TEXT;
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS action           TEXT;
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS cognitive_signals JSONB;
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS status          TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS scheduled_time  TIMESTAMPTZ;
ALTER TABLE IF EXISTS intents      ADD COLUMN IF NOT EXISTS reminder_sent   BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE IF EXISTS memory_chunks ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE IF EXISTS sally_queries ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- ── recordings ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS recordings (
    id          SERIAL PRIMARY KEY,
    audio_file  TEXT,
    status      TEXT NOT NULL DEFAULT 'uploaded',
    device_id   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_recordings_device_created ON recordings(device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recordings_status         ON recordings(status);

-- ── transcripts ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS transcripts (
    id            SERIAL PRIMARY KEY,
    recording_id  INTEGER REFERENCES recordings(id) ON DELETE CASCADE,
    text          TEXT,       -- stores encrypted file path (.txt.enc)
    device_id     TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_transcripts_recording     ON transcripts(recording_id);
CREATE INDEX IF NOT EXISTS idx_transcripts_device_created ON transcripts(device_id, created_at DESC);

-- ── summaries ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS summaries (
    id            SERIAL PRIMARY KEY,
    recording_id  INTEGER REFERENCES recordings(id) ON DELETE CASCADE,
    summary       TEXT,       -- stores encrypted file path (_summary.json.enc)
    device_id     TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_summaries_recording ON summaries(recording_id);
CREATE INDEX IF NOT EXISTS idx_summaries_device    ON summaries(device_id, created_at DESC);

-- ── intents ───────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS intents (
    id                SERIAL PRIMARY KEY,
    recording_id      INTEGER REFERENCES recordings(id) ON DELETE SET NULL,
    device_id         TEXT,
    task              TEXT NOT NULL DEFAULT '',
    intent_type       TEXT NOT NULL DEFAULT 'general',
    temporal_cue      TEXT,
    raw_quote         TEXT,
    semantic_score    NUMERIC(5,3),
    temporal_score    NUMERIC(5,3),
    cognitive_score   NUMERIC(5,3),
    fused_confidence  NUMERIC(5,3),
    decision          TEXT,        -- 'act' | 'confirm' | 'log' | 'ignore'
    action            TEXT,        -- 'notify' | 'flag' | 'log_only' | 'none'
    cognitive_signals JSONB,
    status            TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'completed' | 'ignored'
    scheduled_time    TIMESTAMPTZ,
    reminder_sent     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_intents_device_created ON intents(device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_intents_decision       ON intents(decision);
CREATE INDEX IF NOT EXISTS idx_intents_status         ON intents(status);
CREATE INDEX IF NOT EXISTS idx_intents_scheduled      ON intents(scheduled_time) WHERE scheduled_time IS NOT NULL;

-- ── voice profiles ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS voice_profiles (
    id          SERIAL PRIMARY KEY,
    device_id   TEXT NOT NULL UNIQUE,
    label       TEXT NOT NULL DEFAULT 'owner',
    embedding   TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── RAG memory chunks ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS memory_chunks (
    id            SERIAL PRIMARY KEY,
    recording_id  INTEGER REFERENCES recordings(id) ON DELETE CASCADE,
    device_id     TEXT,
    content       TEXT NOT NULL,
    embedding     vector(384),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_memory_device   ON memory_chunks(device_id);
CREATE INDEX IF NOT EXISTS idx_memory_created  ON memory_chunks(device_id, created_at DESC);

-- ── Sally Q&A ──────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sally_queries (
    id                 SERIAL PRIMARY KEY,
    device_id          TEXT,
    recording_id       INTEGER REFERENCES recordings(id) ON DELETE SET NULL,
    question           TEXT NOT NULL,
    answer             TEXT,
    source_chunks      TEXT,
    transcript_context TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sally_device_created ON sally_queries(device_id, created_at DESC);

-- ── hourly summary cache ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hourly_summaries (
    id            SERIAL PRIMARY KEY,
    device_id     TEXT NOT NULL,
    summary_date  DATE NOT NULL,
    summary_hour  SMALLINT NOT NULL CHECK (summary_hour BETWEEN 0 AND 23),
    summary_json  JSONB NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_hourly UNIQUE (device_id, summary_date, summary_hour)
);

-- ── window summaries (6h rolling and whole-day) ───────────────────────────────

CREATE TABLE IF NOT EXISTS window_summaries (
    id              SERIAL PRIMARY KEY,
    device_id       TEXT NOT NULL,
    window_type     TEXT NOT NULL CHECK (window_type IN ('6h','day','24h')),
    window_start    TIMESTAMPTZ NOT NULL,
    window_end      TIMESTAMPTZ NOT NULL,
    summary_json    JSONB NOT NULL,
    recording_ids   INTEGER[],
    intent_ids      INTEGER[],
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_window UNIQUE (device_id, window_type, window_start)
);
CREATE INDEX IF NOT EXISTS idx_window_device_type ON window_summaries(device_id, window_type, window_start DESC);

-- ── user-created reminders ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS reminders (
    id              SERIAL PRIMARY KEY,
    device_id       TEXT NOT NULL,
    intent_id       INTEGER REFERENCES intents(id) ON DELETE SET NULL,
    title           TEXT NOT NULL,
    notes           TEXT,
    scheduled_time  TIMESTAMPTZ,
    repeat_rule     TEXT NOT NULL DEFAULT 'none',
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','resolved','snoozed')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_reminders_device_status ON reminders(device_id, status);
CREATE INDEX IF NOT EXISTS idx_reminders_scheduled     ON reminders(scheduled_time) WHERE status = 'pending';

-- ── API tokens ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS api_tokens (
    id          SERIAL PRIMARY KEY,
    device_id   TEXT NOT NULL,
    token_hash  TEXT NOT NULL UNIQUE,   -- SHA-256 hex of the raw bearer token
    label       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used   TIMESTAMPTZ
);
