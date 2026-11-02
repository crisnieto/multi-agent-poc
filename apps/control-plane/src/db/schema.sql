CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  actor_id TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS requests (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id),
  text TEXT NOT NULL,
  status TEXT NOT NULL,
  final_text TEXT,
  error_code TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS requests_session_created ON requests(session_id, created_at);
CREATE TABLE IF NOT EXISTS request_keys (
  session_id TEXT NOT NULL REFERENCES sessions(id),
  idempotency_key TEXT NOT NULL,
  request_id TEXT NOT NULL UNIQUE REFERENCES requests(id),
  PRIMARY KEY (session_id, idempotency_key)
);
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT REFERENCES requests(id),
  session_id TEXT,
  actor_id TEXT,
  worker_id TEXT,
  type TEXT NOT NULL,
  source TEXT NOT NULL,
  payload TEXT NOT NULL,
  observed_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS events_request_id ON events(request_id, id);
CREATE INDEX IF NOT EXISTS events_session_id ON events(session_id, id);
