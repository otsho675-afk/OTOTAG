"""Read phpMyAdmin INSERT data without executing SQL or printing credentials."""
import json
import re
import sys
from collections import Counter
from pathlib import Path


def rows(values):
    i = 0
    while i < len(values):
        if values[i] != '(':
            i += 1
            continue
        i += 1
        row = []
        while True:
            while values[i].isspace():
                i += 1
            if values[i] == "'":
                i += 1
                parts = []
                while True:
                    c = values[i]
                    i += 1
                    if c == '\\':
                        c = values[i]
                        i += 1
                        parts.append({'n': '\n', 'r': '\r', 't': '\t', '0': '\0', 'Z': '\x1a'}.get(c, c))
                    elif c == "'":
                        if values[i:i+1] == "'":
                            parts.append("'")
                            i += 1
                        else:
                            break
                    else:
                        parts.append(c)
                value = ''.join(parts)
            else:
                start = i
                while values[i] not in ',)':
                    i += 1
                value = values[start:i].strip()
                value = None if value.upper() == 'NULL' else value
            row.append(value)
            while values[i].isspace():
                i += 1
            delimiter = values[i]
            i += 1
            if delimiter == ')':
                yield row
                break
            if delimiter != ',':
                raise ValueError('Unexpected SQL value delimiter')


def read_dump(path):
    sql = Path(path).read_text(encoding='utf-8-sig')
    tables = {}
    # A statement ends only at an unquoted semicolon.
    quoted = False
    escaped = False
    start = 0
    for i, c in enumerate(sql):
        if escaped:
            escaped = False
            continue
        if quoted and c == '\\':
            escaped = True
        elif c == "'":
            quoted = not quoted
        elif c == ';' and not quoted:
            statement = sql[start:i]
            start = i+1
            match = re.search(r'INSERT INTO `([^`]+)`\s*\((.*?)\) VALUES\s*(.*)', statement, re.S)
            if match:
                table, columns, data = match.groups()
                columns = re.findall(r'`([^`]+)`', columns)
                for row in rows(data):
                    if len(row) != len(columns):
                        raise ValueError(f'{table}: column count mismatch')
                    tables.setdefault(table, []).append(dict(zip(columns, row)))
    return sql, tables


def audit(path):
    sql, tables = read_dump(path)
    report = {'row_counts': {k: len(v) for k, v in tables.items()}, 'orphans': {}}
    links = {
        'vehicles': [('customer_id', 'users')],
        'vehicle_records': [('vehicle_id', 'vehicles')],
        'notifications': [('user_id', 'users')],
        'jobs': [('customer_id', 'users'), ('provider_id', 'users')],
        'bids': [('job_id', 'jobs'), ('provider_id', 'users')],
        'messages': [('job_id', 'jobs'), ('sender_id', 'users'), ('receiver_id', 'users')],
        'provider_cars': [('provider_id', 'users')],
        'rentacar_listings': [('company_id', 'users')],
        'rentacar_bids': [('listing_id', 'rentacar_listings'), ('customer_id', 'users')],
        'ratings': [('job_id', 'jobs'), ('provider_id', 'users'), ('customer_id', 'users')],
        'in_app_purchases': [('user_id', 'users')],
        'live_locations': [('user_id', 'users')],
    }
    for table, columns in links.items():
        for column, parent in columns:
            ids = {r.get('id') for r in tables.get(parent, [])}
            invalid = [r.get('id', r.get(column)) for r in tables.get(table, [])
                       if r.get(column) not in (None, '0', '') and r.get(column) not in ids]
            if invalid:
                report['orphans'][table+'.'+column] = invalid
    report['outbox_status'] = dict(Counter(r['status'] for r in tables.get('notification_outbox', [])))
    report['user_status'] = dict(Counter(r['status'] for r in tables.get('users', [])))
    report['duplicate_vehicle_owner_plate'] = [list(k) for k, n in Counter(
        (r['customer_id'], (r['plate'] or '').upper().replace(' ', ''))
        for r in tables.get('vehicles', [])).items() if n > 1]
    report['invalid_outbox_json'] = []
    for row in tables.get('notification_outbox', []):
        try:
            json.loads(row['payload'])
        except (ValueError, TypeError):
            report['invalid_outbox_json'].append(row['id'])
    report['duplicate_oauth'] = [n for k, n in Counter(
        (r.get('oauth_provider'), r.get('oauth_id')) for r in tables.get('users', [])
        if r.get('oauth_id')).items() if n > 1]
    return report


if __name__ == '__main__':
    print(json.dumps(audit(sys.argv[1]), ensure_ascii=False, indent=2))
