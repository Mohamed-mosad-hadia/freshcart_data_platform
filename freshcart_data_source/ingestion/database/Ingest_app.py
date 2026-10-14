
"""
PostgreSQL (SQLAlchemy) -> ClickHouse bronze ingestion.

  python pg_to_ch_bronze.py init                       # create tables in ClickHouse
  python pg_to_ch_bronze.py full                       # one-time full load (all tables)
  python pg_to_ch_bronze.py incremental                # catch up all finished Cairo days
  python pg_to_ch_bronze.py incremental --day 2026-10-12 [--table orders]

Design
  * Columns, primary keys, nullability and types are READ FROM POSTGRES (reflection),
    so nothing is declared by hand. ClickHouse types are derived from them.
  * Bronze = version history. Every row version lands in the partition of the
    Cairo business day in which it was created/changed (coalesce(updated_at, created_at)).
  * Idempotent, no staging tables: before loading day D the script reads the
    version keys (primary key + change timestamp) already stored for D and inserts
    only versions that are not there yet. Re-running a day inserts 0 rows, and a
    half-failed run is completed by the next run.
  * Nothing is cleaned. Bronze tables store only the raw source columns.

Layout in ClickHouse
  bronze_app.<table>                     e.g. bronze_app.orders
  freshcart_dwh.etl_load_log             run log / watermark

  NOTE: ClickHouse has no sub-database schemas, so bronze_app is its own
  ClickHouse database (equivalent to a schema in PostgreSQL terms).

Secrets are read with os.environ, so load your .env into the shell first:
     set -a; source .env; set +a; python pg_to_ch_bronze.py init
  needed variables:
     SOURCE_DB_USER, SOURCE_DB_PASSWORD      (PostgreSQL)
     CLICKHOUSE_PASSWORD                     (ClickHouse)
Non-secret settings (hosts, ports, database names) are plain constants below.
"""
import argparse
import datetime as dt
import os
import uuid
from zoneinfo import ZoneInfo  # needs up-to-date tzdata (Egypt DST since 2023)

import clickhouse_connect
import sqlalchemy as sa

# ------------------------------------------------------------------ settings
# PostgreSQL source
PG_HOST, PG_PORT, PG_DB = "localhost", 5433, "freshcart_source"
PG_SCHEMA = "app"                            # schema of the source tables
# ClickHouse target
CH_HOST, CH_PORT, CH_USER = "localhost", 8123, "freshcart_user"
DB = "freshcart_dwh"                         # houses the ETL log
BRONZE_DB = "bronze_app"                     # dedicated database = bronze schema
SRC_SYSTEM = PG_DB                           # label written to _source_system

# Source tables to ingest. Everything else comes from Postgres itself.
SOURCE_TABLES = ["stores", "customers", "products", "product_prices",
                 "orders", "order_items", "payments"]

CAIRO, UTC = ZoneInfo("Africa/Cairo"), ZoneInfo("UTC")
BATCH = 100_000
LOOKBACK_DAYS = 2   # nightly re-run of the last N days (safe: loads are idempotent)


CHG = "coalesce(updated_at, created_at)"   # "created or changed" (ClickHouse SQL form)
LOG = f"{DB}.etl_load_log"


# ------------------------------------------------------------------ secrets
def secret(name: str) -> str:
    """Read a secret from the environment (your .env must be loaded first, see top)."""
    value = os.environ.get(name)
    if value is None:
        raise SystemExit(f"Missing {name}: load your .env first "
                         f"(e.g.  set -a; source .env; set +a)")
    return value


# ---- PostgreSQL via SQLAlchemy ------------------------------------------------
# URL.create escapes special characters in passwords (@, :, / ...) safely
engine = sa.create_engine(
    sa.URL.create(
        "postgresql+psycopg",
        username=secret("SOURCE_DB_USER"), password=secret("SOURCE_DB_PASSWORD"),
        host=PG_HOST, port=PG_PORT, database=PG_DB),
    pool_pre_ping=True)
_md = sa.MetaData()
_reflected: dict[str, sa.Table] = {}

# ---- ClickHouse -----------------------------------------------------------------
ch = clickhouse_connect.get_client(
    host=CH_HOST, port=CH_PORT, username=CH_USER,
    password=secret("CLICKHOUSE_PASSWORD"))


def tbl(t):
    # bronze_app is its own ClickHouse database, acting as the bronze schema
    # e.g.  bronze_app.orders, bronze_app.customers
    return f"{BRONZE_DB}.{t}"


# ------------------------------------------------- schema derived from Postgres
def pg_table(t) -> sa.Table:
    """Reflect the source table once and validate what the loader relies on."""
    if t not in _reflected:
        tb = sa.Table(t, _md, schema=PG_SCHEMA, autoload_with=engine)
        for c in ("created_at", "updated_at"):
            if c not in tb.c:
                raise SystemExit(f"[{t}] has no {c} column")
            typ = tb.c[c].type
            if not (isinstance(typ, sa.DateTime) and typ.timezone):
                raise SystemExit(
                    f"[{t}].{c} is {typ}, not timestamptz. The Cairo day boundaries "
                    f"assume timestamptz; tell me whether it stores UTC or Cairo time.")
        if not list(tb.primary_key.columns):
            raise SystemExit(f"[{t}] has no primary key; the version key needs one")
        _reflected[t] = tb
    return _reflected[t]


def src_cols(t):
    return [c.name for c in pg_table(t).columns]


def pk_cols(t):
    return [c.name for c in pg_table(t).primary_key.columns]


def all_cols(t):
    return src_cols(t)


def ch_type(col: sa.Column) -> str:
    """Postgres column -> ClickHouse type, keeping nullability."""
    typ = col.type
    if isinstance(typ, sa.Boolean):
        base = "Bool"
    elif isinstance(typ, sa.SmallInteger):
        base = "Int16"
    elif isinstance(typ, sa.BigInteger):
        base = "Int64"
    elif isinstance(typ, sa.Integer):
        base = "Int32"
    elif isinstance(typ, sa.Float):                 # must precede Numeric (subclass)
        base = "Float32" if (typ.precision or 53) <= 24 else "Float64"
    elif isinstance(typ, sa.Numeric):
        if typ.precision is None:
            raise SystemExit(f"{col.table.name}.{col.name}: numeric without precision "
                             f"can't be mapped to Decimal; tell me how to load it (String?)")
        base = f"Decimal({typ.precision}, {typ.scale or 0})"
    elif isinstance(typ, sa.DateTime):
        base = "DateTime64(6, 'UTC')" if typ.timezone else "DateTime64(6)"
    elif isinstance(typ, sa.Date):
        base = "Date"
    elif isinstance(typ, sa.String):                # text, varchar, char(n)
        base = "String"
    else:
        raise SystemExit(f"{col.table.name}.{col.name}: unsupported Postgres type {typ!r}")
    return f"Nullable({base})" if col.nullable else base


def cairo_midnight_utc(d: dt.date) -> dt.datetime:
    return dt.datetime.combine(d, dt.time(), tzinfo=CAIRO).astimezone(UTC)


def today_cairo() -> dt.date:
    return dt.datetime.now(CAIRO).date()


def extract(t, start=None, end=None):
    """
    Stream rows via a server-side cursor, as lists of tuples.
    Last element of each tuple = Cairo business date of the change.
    start=None -> everything before `end` (full load).
    """
    tb = pg_table(t)
    chg = sa.func.coalesce(tb.c.updated_at, tb.c.created_at)
    business_date = sa.cast(sa.func.timezone("Africa/Cairo", chg), sa.Date)
    stmt = sa.select(*tb.columns, business_date.label("business_date"))
    if start is not None:
        stmt = stmt.where(chg >= start)
    stmt = stmt.where(chg < end)

    with engine.connect() as conn:
        conn = conn.execution_options(
            isolation_level="REPEATABLE READ",     # one consistent snapshot
            postgresql_readonly=True,
            stream_results=True,                   # server-side cursor
            yield_per=BATCH)
        for part in conn.execute(stmt).partitions():
            yield [tuple(r) for r in part]


def write(t, rows):
    # r[:-1] strips the business_date appended by extract(); only source cols are stored
    data = [list(r[:-1]) for r in rows]
    ch.insert(tbl(t), data, column_names=all_cols(t),
              settings={"max_partitions_per_insert_block": 100_000})
    return len(data)


# ---- version keys (idempotency without staging) ---------------------------------
def _norm(v):
    """Make datetimes comparable (tz-aware UTC) whichever driver produced them."""
    if isinstance(v, dt.datetime):
        return v.replace(tzinfo=UTC) if v.tzinfo is None else v.astimezone(UTC)
    return v


def existing_versions(t, day):
    """Version keys already stored in bronze for this business day (Cairo date)."""
    key = ", ".join(pk_cols(t) + [CHG])
    res = ch.query(
        f"SELECT {key} FROM {tbl(t)} "
        f"WHERE toDate({CHG}, 'Africa/Cairo') = '{day.isoformat()}'"
    )
    return {tuple(_norm(v) for v in row) for row in res.result_rows}


def version_key(t, row, idx):
    pk = tuple(_norm(row[idx[c]]) for c in pk_cols(t))
    changed = row[idx["updated_at"]] or row[idx["created_at"]]
    return pk + (_norm(changed),)


# ---- run log --------------------------------------------------------------------
def log(t, day, load_type, batch_id, read, inserted):
    ch.insert(LOG,
              [[t, day, load_type, batch_id, read, inserted, "ok",
                dt.datetime.now(UTC)]],
              column_names=["source_table", "business_date", "load_type", "batch_id",
                            "rows_read", "rows_inserted", "status", "finished_at"])


def last_full_exists(t):
    return ch.query(f"SELECT count() FROM {LOG} WHERE source_table=%(t)s "
                    "AND load_type='full' AND status='ok'",
                    parameters={"t": t}).first_row[0] > 0


def watermark(t):
    """Last loaded business day since the most recent full load."""
    return ch.query(
        f"SELECT max(business_date) FROM {LOG} "
        "WHERE source_table=%(t)s AND status='ok' AND finished_at >= "
        f"(SELECT max(finished_at) FROM {LOG} "
        " WHERE source_table=%(t)s AND load_type='full' AND status='ok')",
        parameters={"t": t}).first_row[0]


# --------------------------------------------------------------------- init
def init():
    ch.command(f"CREATE DATABASE IF NOT EXISTS {DB}")       # freshcart_dwh (for the log)
    ch.command(f"CREATE DATABASE IF NOT EXISTS {BRONZE_DB}")  # bronze_app (the bronze schema)
    for t in SOURCE_TABLES:
        cols = [f"{c.name} {ch_type(c)}" for c in pg_table(t).columns]
        order = ", ".join(pk_cols(t))
        ddl = (f"CREATE TABLE IF NOT EXISTS {tbl(t)} (\n  " + ",\n  ".join(cols) +
               f"\n) ENGINE = MergeTree"
               f" PARTITION BY toDate({CHG}, 'Africa/Cairo')"
               f" ORDER BY ({order})")
        ch.command(ddl)
        print(f"[{t}] ready: {tbl(t)}")
    ch.command(f"""
        CREATE TABLE IF NOT EXISTS {LOG} (
            source_table  String,
            business_date Date,
            load_type     LowCardinality(String),
            batch_id      UUID,
            rows_read     UInt64,
            rows_inserted UInt64,
            status        LowCardinality(String),
            finished_at   DateTime64(3, 'UTC')
        ) ENGINE = MergeTree ORDER BY (source_table, finished_at)""")


# ---------------------------------------------------------------- full load
def full_load(t, force=False):
    if last_full_exists(t) and not force:
        print(f"[{t}] full load already done; use --force to redo")
        return
    cutoff_day = today_cairo()                 # first day NOT in the full load
    cutoff = cairo_midnight_utc(cutoff_day)
    batch_id, total = uuid.uuid4(), 0

    ch.command(f"TRUNCATE TABLE {tbl(t)}")     # re-runnable
    for rows in extract(t, end=cutoff):
        total += write(t, rows)
    # watermark = last day covered; incremental resumes at cutoff_day
    log(t, cutoff_day - dt.timedelta(days=1), "full", batch_id, total, total)
    print(f"[{t}] full load: {total} rows (< {cutoff_day} Cairo)")


# -------------------------------------------------------------- incremental
def load_day(t, day):
    start = cairo_midnight_utc(day)
    end = cairo_midnight_utc(day + dt.timedelta(days=1))
    batch_id, read, inserted = uuid.uuid4(), 0, 0
    idx = {c: i for i, c in enumerate(src_cols(t))}

    seen = existing_versions(t, day)
    for rows in extract(t, start=start, end=end):
        read += len(rows)
        new = [r for r in rows if version_key(t, r, idx) not in seen]
        if new:
            inserted += write(t, new)
    log(t, day, "incremental", batch_id, read, inserted)
    print(f"[{t}] {day}: read {read}, inserted {inserted}")


def incremental(t, day=None, lookback=LOOKBACK_DAYS):
    if not last_full_exists(t):
        raise SystemExit(f"[{t}] run the full load first")
    today = today_cairo()
    if day:
        if day >= today:
            raise SystemExit(f"{day} is not finished yet in Cairo (today is {today})")
        return load_day(t, day)
    d = watermark(t) + dt.timedelta(days=1) - dt.timedelta(days=lookback)
    while d < today:                            # only completed Cairo days
        load_day(t, d)
        d += dt.timedelta(days=1)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("mode", nargs="?", choices=["init", "full", "incremental"], default="incremental")
    p.add_argument("--table", choices=SOURCE_TABLES)
    p.add_argument("--day", type=dt.date.fromisoformat)
    p.add_argument("--lookback", type=int, default=LOOKBACK_DAYS)
    p.add_argument("--force", action="store_true")
    a = p.parse_args()

    if a.mode == "init":
        init()
    else:
        for tbl_name in ([a.table] if a.table else SOURCE_TABLES):
            if a.mode == "full":
                full_load(tbl_name, a.force)
            else:
                incremental(tbl_name, a.day, a.lookback)



#     .-""""-.
#    /        \
#   |  o    o  |
#   |    __    |
#   |  ( __ )  |
#    \  \__/  /
#     '------'
#     |  ||  |
#    /|  ||  |\
#   (_)      (_)
#
#   😭  why is ETL always crying?
#       because the data never stops flowing...

