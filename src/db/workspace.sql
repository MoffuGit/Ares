CREATE TABLE IF NOT EXISTS workspace (
    id INTEGER PRIMARY KEY,
    paths TEXT NOT NULL,
    session TEXT,
    window_x REAL,
    window_y REAL,
    window_width REAL,
    window_height REAL,
    timestamp INTEGER DEFAULT (unixepoch())
);
