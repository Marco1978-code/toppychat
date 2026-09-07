// ToppyChat relay server
//
// Scopo: fare da "postino" in tempo reale tra due o piu' telefoni che usano
// l'app ToppyChat. Non salva MAI i messaggi su disco: tutto vive solo in
// memoria (RAM) del processo e sparisce al riavvio del server. Se il
// destinatario e' online il messaggio viene inoltrato subito; se e' offline
// viene tenuto in una piccola coda in memoria (con limiti) finche' non si
// riconnette, oppure scartato dopo un tempo massimo.
//
// Oltre ai messaggi di testo, il relay inoltra anche allegati (type:'file',
// dati in base64) e ricevute di consegna/lettura (type:'receipt', le
// "spunte" stile chat) con lo stesso identico meccanismo.
//
// Il salvataggio "vero" delle conversazioni avviene solo sui telefoni, in
// locale, come file di testo in Download/ToppyChat/ (vedi la app Flutter).

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const RELAY_TOKEN = process.env.RELAY_TOKEN || '';

// Quanti messaggi di testo/ricevute tenere in coda al massimo per un
// numero offline.
const MAX_QUEUE_PER_PHONE = 200;
// Quanti allegati (type:'file') tenere in coda al massimo per un numero
// offline: molto piu' basso dei messaggi di testo perche' ogni allegato
// puo' pesare qualche megabyte in RAM.
const MAX_QUEUED_FILES_PER_PHONE = 5;
// Dimensione massima di un allegato in base64 (~5 MB originali, il base64
// li gonfia di circa un terzo).
const MAX_FILE_BASE64_BYTES = 7 * 1024 * 1024;
// Dopo quanto tempo (ms) un messaggio in coda viene scartato se il
// destinatario non si e' mai riconnesso. Default: 24 ore.
const MAX_QUEUE_AGE_MS = 24 * 60 * 60 * 1000;

if (!RELAY_TOKEN) {
  console.warn(
    '[avviso] RELAY_TOKEN non impostato: chiunque conosca l\'indirizzo del server potra\' collegarsi. ' +
    'Imposta la variabile d\'ambiente RELAY_TOKEN prima di usare il server sul serio.'
  );
}

// phone (string) -> WebSocket connesso in questo momento
const connected = new Map();
// phone (string) -> array di { type, payload, queuedAt }
const queues = new Map();

function normalizePhone(phone) {
  return String(phone || '').trim();
}

function send(ws, payload) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

function queueItem(toPhone, type, payload) {
  let q = queues.get(toPhone);
  if (!q) {
    q = [];
    queues.set(toPhone, q);
  }
  q.push({ type, payload, queuedAt: Date.now() });

  if (type === 'file') {
    // Teniamo al massimo N allegati in coda per numero: se ce ne sono
    // gia' troppi, scartiamo il piu' vecchio (non i messaggi di testo).
    let fileCount = 0;
    for (let i = q.length - 1; i >= 0; i--) {
      if (q[i].type !== 'file') continue;
      fileCount++;
      if (fileCount > MAX_QUEUED_FILES_PER_PHONE) {
        q.splice(i, 1);
      }
    }
  }

  if (q.length > MAX_QUEUE_PER_PHONE) {
    // Scartiamo il piu' vecchio in assoluto per restare leggeri.
    q.shift();
  }
}

function flushQueue(phone, ws) {
  const q = queues.get(phone);
  if (!q || q.length === 0) return;
  const now = Date.now();
  for (const item of q) {
    if (now - item.queuedAt <= MAX_QUEUE_AGE_MS) {
      send(ws, { type: item.type, ...item.payload });
    }
  }
  queues.delete(phone);
}

// Inoltra subito [payload] (con 'type' aggiunto) al numero [to] se online,
// altrimenti lo mette in coda. Usato per message/file/receipt allo stesso
// modo.
function routeOrQueue(type, to, payload) {
  const recipientWs = connected.get(to);
  if (recipientWs && recipientWs.readyState === recipientWs.OPEN) {
    send(recipientWs, { type, ...payload });
    return true;
  }
  queueItem(to, type, payload);
  return false;
}

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      ok: true,
      connected: connected.size,
      queuedPhones: queues.size,
    }));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('ToppyChat relay attivo. Nessun messaggio viene salvato su disco.');
});

const wss = new WebSocketServer({ server, maxPayload: MAX_FILE_BASE64_BYTES + 64 * 1024 });

wss.on('connection', (ws) => {
  let registeredPhone = null;

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (err) {
      send(ws, { type: 'error', message: 'JSON non valido' });
      return;
    }

    if (data.type === 'register') {
      if (RELAY_TOKEN && data.token !== RELAY_TOKEN) {
        send(ws, { type: 'error', message: 'Token non valido' });
        ws.close();
        return;
      }
      const phone = normalizePhone(data.phone);
      if (!phone) {
        send(ws, { type: 'error', message: 'Numero di telefono mancante' });
        return;
      }
      registeredPhone = phone;
      connected.set(phone, ws);
      send(ws, { type: 'registered', phone });
      flushQueue(phone, ws);
      return;
    }

    if (!registeredPhone) {
      send(ws, { type: 'error', message: 'Devi registrarti prima di inviare messaggi' });
      return;
    }

    if (data.type === 'message') {
      const to = normalizePhone(data.to);
      const text = String(data.text || '');
      const id = String(data.id || '');
      const ts = Number(data.ts) || Date.now();
      if (!to || !text) {
        send(ws, { type: 'error', message: 'Destinatario o testo mancante' });
        return;
      }

      const delivered = routeOrQueue('message', to, { from: registeredPhone, text, id, ts });
      send(ws, { type: 'ack', id, delivered, queued: !delivered });
      return;
    }

    if (data.type === 'file') {
      const to = normalizePhone(data.to);
      const id = String(data.id || '');
      const fileName = String(data.fileName || 'file');
      const mimeType = String(data.mimeType || 'application/octet-stream');
      const dataBase64 = String(data.data || '');
      const ts = Number(data.ts) || Date.now();
      if (!to || !dataBase64) {
        send(ws, { type: 'error', message: 'Destinatario o allegato mancante' });
        return;
      }
      if (dataBase64.length > MAX_FILE_BASE64_BYTES) {
        send(ws, { type: 'error', message: 'Allegato troppo grande', id });
        return;
      }

      const delivered = routeOrQueue('file', to, {
        from: registeredPhone,
        id,
        fileName,
        mimeType,
        data: dataBase64,
        ts,
      });
      send(ws, { type: 'ack', id, delivered, queued: !delivered });
      return;
    }

    if (data.type === 'receipt') {
      const to = normalizePhone(data.to);
      const id = String(data.id || '');
      const status = String(data.status || '');
      if (!to || !id || !status) {
        send(ws, { type: 'error', message: 'Ricevuta incompleta' });
        return;
      }
      routeOrQueue('receipt', to, { from: registeredPhone, id, status });
      return;
    }

    if (data.type === 'ping') {
      send(ws, { type: 'pong' });
      return;
    }

    send(ws, { type: 'error', message: `Tipo messaggio sconosciuto: ${data.type}` });
  });

  ws.on('close', () => {
    if (registeredPhone && connected.get(registeredPhone) === ws) {
      connected.delete(registeredPhone);
    }
  });
});

server.listen(PORT, () => {
  console.log(`ToppyChat relay in ascolto sulla porta ${PORT} (zero persistenza su disco).`);
});
