import re

_READ_VERBS = {"SELECT", "SHOW", "DESCRIBE", "DESC", "EXISTS", "WITH"}
_INSERT_RE = re.compile(
    r"INSERT\s+INTO\s+([\w.`\"]+)\s*(?:\(([^)]*)\))?\s*VALUES\s*;?\s*$",
    re.IGNORECASE | re.DOTALL,
)


class CHClient:
    """Gives a clickhouse-connect client the clickhouse-driver style API."""

    def __init__(self, client):
        self._c = client

    def execute(self, query, params=None, *args, **kwargs):
        q = query.strip()
        verb = q.split(None, 1)[0].upper()

        # INSERT INTO t (a, b) VALUES  + list of rows
        if verb == "INSERT" and isinstance(params, (list, tuple)):
            m = _INSERT_RE.match(q)
            if not m:
                raise ValueError(f"Unsupported INSERT form: {q[:120]}")
            table = m.group(1).replace("`", "").replace('"', "")
            cols = [c.strip().strip("`") for c in m.group(2).split(",")] if m.group(2) else None
            if params:
                self._c.insert(table, params, column_names=cols or "*")
            return len(params)

        # Queries that return rows
        if verb in _READ_VERBS:
            return self._c.query(q, parameters=params).result_rows

        # DDL and everything else (CREATE, ALTER, DROP, TRUNCATE, ...)
        self._c.command(q, parameters=params)
        return []

    def disconnect(self):
        self._c.close()

    def __getattr__(self, name):  # fall through to the real client
        return getattr(self._c, name)