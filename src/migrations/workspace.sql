CREATE TABLE IF NOT EXISTS workspace (
    id INTEGER PRIMARY KEY,
    paths TEXT NOT NULL DEFAULT '',
    session TEXT,
    window_x REAL,
    window_y REAL,
    window_width REAL,
    window_height REAL,
    left_dock REAL,
    right_dock REAL,
    timestamp INTEGER DEFAULT (unixepoch())
);
