<?php
// Shared configuration for the API and its command-line installer.
function readServerEnvironment($path) {
    if (!is_file($path)) return [];
    $handle = fopen($path, 'rb');
    if (!$handle) throw new RuntimeException('.env dosyası okunamıyor.');
    flock($handle, LOCK_SH);
    $source = stream_get_contents($handle);
    flock($handle, LOCK_UN);
    fclose($handle);
    return parseServerEnvironment($source);
}
function parseServerEnvironment($source) {
    $source = preg_replace('/^\xEF\xBB\xBF/', '', $source);
    $values = [];
    foreach (preg_split('/\r\n|\n|\r/', $source) as $index => $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || $line[0] === ';') continue;
        if (!preg_match('/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/D', $line, $match)) {
            throw new RuntimeException('.env biçimi hatalı; satır '.($index + 1).'.');
        }
        $value = trim($match[2]);
        if ($value !== '' && ($value[0] === '"' || $value[0] === "'")) {
            $quote = $value[0];
            if (!preg_match('/^'.preg_quote($quote, '/').'(.*)'.preg_quote($quote, '/').'\s*(?:[#;].*)?$/D', $value, $quoted)) {
                throw new RuntimeException('.env tırnağı kapanmamış; satır '.($index + 1).'.');
            }
            $value = $quoted[1];
        } else {
            $value = preg_replace('/\s+[#;].*$/', '', $value);
        }
        if ($match[1]==='ALLOWED_ORIGINS') {
            // A copied Markdown link is not an origin. Accept only matching
            // link text/target and preserve the existing strict origin checks.
            $value=str_replace('\\*','*',$value);
            if (preg_match('/^\[([^\]]+)\]\(([^)]+)\)$/D',$value,$link) && $link[1]===$link[2]) $value=$link[1];
        }
        $values[$match[1]] = $value;
    }
    return $values;
}
function serverConfig($name, $default = '') {
    global $env;
    $value = getenv($name);
    if ($value !== false) return $value;
    if (array_key_exists($name, $env ?? [])) return $env[$name];
    $aliases = ['DB_PASS'=>'DB_PASSWORD', 'DB_NAME'=>'DB_DATABASE', 'DB_USER'=>'DB_USERNAME'];
    $alias = $aliases[$name] ?? null;
    if ($alias) {
        $value = getenv($alias);
        if ($value !== false) return $value;
        if (array_key_exists($alias, $env ?? [])) return $env[$alias];
    }
    return $default;
}
function apiOriginAllowed($origin, $patterns) {
    if (!$origin || preg_match('/[\r\n]/', $origin)) return false;
    foreach ($patterns as $pattern) {
        if ($pattern === $origin) return true;
        // Wildcard ports are supported only for local Flutter development.
        if (in_array($pattern, ['http://localhost:*', 'http://127.0.0.1:*', 'http://[::1]:*'], true)) {
            $prefix = substr($pattern, 0, -1);
            if (strpos($origin, $prefix) === 0 && preg_match('/^[0-9]{1,5}$/D', substr($origin, strlen($prefix)))) {
                $port = (int) substr($origin, strlen($prefix));
                if ($port > 0 && $port <= 65535) return true;
            }
        }
    }
    return false;
}
function availableAdImages($ads, $directory) {
    foreach ($ads as &$ad) {
        $url = trim($ad['image_url'] ?? '');
        $relative = ltrim($url, '/');
        if (strpos($relative, 'uploads/ads/') === 0) {
            $name = substr($relative, strlen('uploads/ads/'));
            if (!preg_match('/^[A-Za-z0-9_.-]+$/D', $name) || !is_file($directory.'/uploads/ads/'.$name)) $url = null;
        }
        $ad['image_url'] = $url;
    }
    unset($ad);
    return $ads;
}
