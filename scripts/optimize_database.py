"""Apply release-time indexes to the bundled catalog (never writes at app launch)."""
import sqlite3
from pathlib import Path


def optimize(path):
    with sqlite3.connect(path) as db:
        for table in ['stars_brightest_300', 'stars_h3_0', 'stars_h3_1', 'stars_h3_2']:
            db.execute(f'CREATE UNIQUE INDEX IF NOT EXISTS idx_{table}_id ON {table}(id)')
            cell = 'h3_0' if table == 'stars_brightest_300' else table.removeprefix('stars_')
            db.execute(f'CREATE INDEX IF NOT EXISTS idx_{table}_cell_mag ON {table}({cell}, mag)')
        for column in ['hip', 'hd', 'hr']:
            db.execute(f'CREATE INDEX IF NOT EXISTS idx_stars_info_{column} ON stars_info({column})')
        db.execute('CREATE INDEX IF NOT EXISTS idx_constellation_borders_con ON constellation_borders(con)')
        db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_constellations_iau ON constellations(iau)')
        db.execute('CREATE INDEX IF NOT EXISTS idx_constellations_name ON constellations(constellation)')
        db.execute('PRAGMA user_version = 30200')
        db.execute('ANALYZE')
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'


if __name__ == '__main__':
    optimize(Path(__file__).resolve().parents[1] / 'Sources/Resources/stars.sqlite3')
