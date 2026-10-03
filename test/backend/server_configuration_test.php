<?php
require __DIR__.'/../../lib/server_configuration.php';
$count = 0;
function expectConfig($ok, $label) { global $count; if (!$ok) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
$env = parseServerEnvironment("\xEF\xBB\xBFDB_USER=elite\r\nDB_PASSWORD='a#b;!&=c'\r\nDB_DATABASE=elite\nJWT_SECRET=abc # comment\nexport EMPTY=\nLITERAL=false\nQUOTED=\"hello # world\" # comment\n");
expectConfig($env['DB_USER']==='elite','UTF-8 BOM and CRLF');
expectConfig(serverConfig('DB_PASS')==='a#b;!&=c','quoted password punctuation preserved');
expectConfig(serverConfig('DB_NAME')==='elite','database alias');
expectConfig(serverConfig('JWT_SECRET')==='abc','unquoted comment');
expectConfig(serverConfig('EMPTY','fallback')==='','empty value retained');
expectConfig(serverConfig('LITERAL')==='false','literal false retained');
expectConfig(serverConfig('QUOTED')==='hello # world','quoted comment preserved');
expectConfig(apiOriginAllowed('http://localhost:60369',['http://localhost:*']),'Flutter changing localhost port');
expectConfig(apiOriginAllowed('https://eliteagency.sbs',['https://eliteagency.sbs']),'production exact origin');
expectConfig(!apiOriginAllowed('http://localhost.evil.test:60369',['http://localhost:*']),'localhost lookalike denied');
expectConfig(!apiOriginAllowed('http://localhost:60369/path',['http://localhost:*']),'origin with path denied');
expectConfig(!apiOriginAllowed('http://localhost:99999',['http://localhost:*']),'invalid port denied');
expectConfig(!apiOriginAllowed('https://evil.test',['*']),'arbitrary wildcard denied');
try { parseServerEnvironment('JWT_SECRET="broken'); expectConfig(false,'malformed env'); }
catch (RuntimeException $e) { expectConfig(strpos($e->getMessage(),'satır 1')!==false,'malformed env identifies line without secret'); }
$copied=parseServerEnvironment('ALLOWED_ORIGINS="[https://eliteagency.sbs,http://localhost:\\*](https://eliteagency.sbs,http://localhost:*)"');
expectConfig(apiOriginAllowed('https://eliteagency.sbs',explode(',',$copied['ALLOWED_ORIGINS'])),'matching Markdown origin link safely normalized');
expectConfig(apiOriginAllowed('http://localhost:53021',explode(',',$copied['ALLOWED_ORIGINS'])),'escaped local wildcard normalized');
$mismatch=parseServerEnvironment('ALLOWED_ORIGINS="[https://eliteagency.sbs](https://evil.test)"');
expectConfig(!apiOriginAllowed('https://evil.test',explode(',',$mismatch['ALLOWED_ORIGINS'])),'mismatched Markdown target cannot widen origin permissions');
echo "\n$count configuration checks passed.\n";
