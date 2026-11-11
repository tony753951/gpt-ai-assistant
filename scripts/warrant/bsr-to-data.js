#!/usr/bin/env node
/* eslint-disable no-console, no-restricted-syntax, no-irregular-whitespace */
/**
 * 把證交所「買賣日報表查詢」下載的 CSV 轉成 public/warrant/data.json。
 *
 * 用法：
 *   node scripts/warrant/bsr-to-data.js --in data/raw --map data/warrants.csv \
 *     [--bars data/bars.csv] [--date 2026-11-10] [--out public/warrant/data.json]
 *
 * --in    CSV 檔或資料夾（會往下找所有 .csv）。交易日從檔名或資料夾名稱取得，
 *         例如 data/raw/2026-11-10/03xxxx.csv 或 03xxxx_20261110.csv；都沒有就用 --date。
 * --map   權證對照表 CSV，欄位：權證代號,標的代號,標的名稱,類型（call/put 或 認購/認售）
 * --bars  （選填）標的日K CSV，欄位：代號,日期,開,高,低,收,成交量(張)
 * --out   輸出檔，已存在時會合併：本次處理到的日期整天覆蓋，其他日期保留。
 */
import fs from 'fs';
import path from 'path';

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) out[key] = true;
      else { out[key] = next; i += 1; }
    }
  }
  return out;
}

function parseCsvLine(line) {
  const cells = [];
  let cur = '';
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i += 1; } else if (ch === '"') quoted = false;
      else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { cells.push(cur); cur = ''; } else cur += ch;
  }
  cells.push(cur);
  return cells.map((c) => c.trim());
}

function readText(file) {
  return fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
}

function readCsv(file) {
  return readText(file).split(/\r?\n/).filter((l) => l.trim()).map(parseCsvLine);
}

function normDate(s) {
  const m = String(s).match(/(\d{4})[-/]?(\d{2})[-/]?(\d{2})/);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

function dateFromPath(file) {
  const parts = file.split(path.sep).reverse();
  for (const p of parts) {
    const m = p.match(/(20\d{2})-?(\d{2})-?(\d{2})/);
    if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  }
  return null;
}

function listCsv(target) {
  const st = fs.statSync(target);
  if (st.isFile()) return [target];
  return fs.readdirSync(target).flatMap((name) => {
    const p = path.join(target, name);
    if (fs.statSync(p).isDirectory()) return listCsv(p);
    return /\.csv$/i.test(name) ? [p] : [];
  });
}

// "1020合　　庫" → { code: '1020', name: '合庫' }
function splitBroker(raw) {
  const s = raw.replace(/[\s　]/g, '');
  return { code: s.slice(0, 4), name: s.slice(4) || s.slice(0, 4) };
}

/** 解析一個買賣日報表 CSV，回傳 { code, brokers: Map(code → {name, buy, sell}) }，金額單位：元 */
function parseBsr(file) {
  const rows = readCsv(file);
  const codeRow = rows.find((r) => /代碼|代號/.test(r[0]));
  if (!codeRow) throw new Error(`${file}: 找不到「股票代碼」列，可能不是買賣日報表 CSV`);
  const code = codeRow[1].replace(/^="?|"$/g, '').replace(/"/g, '').trim();
  const brokers = new Map();
  const add = (cells) => {
    if (cells.length < 5 || !/^\d+$/.test(cells[0])) return;
    const { code: bc, name } = splitBroker(cells[1]);
    const price = Number(cells[2]);
    const buy = Number(cells[3]);
    const sell = Number(cells[4]);
    if (!bc || !Number.isFinite(price)) return;
    const rec = brokers.get(bc) || { name, buy: 0, sell: 0 };
    rec.buy += price * (buy || 0);
    rec.sell += price * (sell || 0);
    brokers.set(bc, rec);
  };
  for (const r of rows) {
    add(r.slice(0, 5));
    add(r.slice(6, 11));
  }
  return { code, brokers };
}

function loadMap(file) {
  const map = new Map();
  if (!file) return map;
  for (const r of readCsv(file)) {
    const [w, u, uname, t] = r;
    if (w && u && !/代號|code/i.test(w)) {
      const type = /put|售/i.test(t || '') ? 'put' : 'call';
      map.set(w.toUpperCase(), { stock: u, name: uname || u, type });
    }
  }
  return map;
}

function loadBars(file) {
  const bars = {};
  if (!file) return bars;
  for (const r of readCsv(file)) {
    const [code, d, o, h, l, c, v] = r;
    const date = normDate(d);
    if (code && date && Number.isFinite(Number(c))) {
      bars[code] = bars[code] || {};
      bars[code][date] = [o, h, l, c, v || 0].map(Number);
    }
  }
  return bars;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.in || !args.map) {
    console.error('用法：node scripts/warrant/bsr-to-data.js --in <CSV檔或資料夾> --map <權證對照表.csv> [--bars <日K.csv>] [--date YYYY-MM-DD] [--out public/warrant/data.json]');
    process.exit(1);
  }
  const outFile = args.out || 'public/warrant/data.json';
  const wmap = loadMap(args.map);
  const fallbackDate = args.date ? normDate(args.date) : null;

  // agg: date → "stock|broker|type" → 淨買超（元）
  const agg = new Map();
  const brokerNames = new Map();
  const stockNames = new Map();
  const unmapped = new Set();
  const vwapHint = new Map(); // "code|date" → { lo, hi, amt, shares }，沒有日K時的備援
  let files = 0;

  for (const file of listCsv(args.in)) {
    const date = dateFromPath(file) || fallbackDate;
    if (!date) {
      console.error(`略過 ${file}：檔名沒有日期，請用 --date 指定或把檔案放進 YYYY-MM-DD 資料夾`);
    } else {
      const { code, brokers } = parseBsr(file);
      files += 1;
      const w = wmap.get(code.toUpperCase());
      if (!w) unmapped.add(code);
      else {
        stockNames.set(w.stock, w.name);
        if (!agg.has(date)) agg.set(date, new Map());
        const day = agg.get(date);
        for (const [bc, rec] of brokers) {
          brokerNames.set(bc, rec.name);
          const key = `${w.stock}|${bc}|${w.type}`;
          day.set(key, (day.get(key) || 0) + rec.buy - rec.sell);
        }
      }
      // 如果這個檔本身就是某個標的，記下成交價區間，日K缺漏時可用
      let lo = Infinity; let hi = -Infinity; let amt = 0; let shares = 0;
      const rows = readCsv(file);
      for (const r of rows) {
        for (const c of [r.slice(0, 5), r.slice(6, 11)]) {
          if (c.length >= 5 && /^\d+$/.test(c[0])) {
            const p = Number(c[2]); const b = Number(c[3]) || 0;
            if (b > 0) { lo = Math.min(lo, p); hi = Math.max(hi, p); amt += p * b; shares += b; }
          }
        }
      }
      if (shares) {
        vwapHint.set(`${code}|${date}`, {
          lo, hi, vwap: amt / shares, lots: Math.round(shares / 1000),
        });
      }
    }
  }

  // 合併既有 data.json
  let data = {
    calendar: [], stocks: [], brokers: [], bars: {}, flows: [],
  };
  if (fs.existsSync(outFile)) data = JSON.parse(readText(outFile));
  const newDates = new Set(agg.keys());
  const flowMap = new Map();
  for (const f of data.flows || []) {
    const key = `${f.stock}|${f.broker}|${f.type}`;
    const days = Object.fromEntries(Object.entries(f.days || {}).filter(([d]) => !newDates.has(d)));
    flowMap.set(key, days);
  }
  for (const [date, day] of agg) {
    for (const [key, yuan] of day) {
      const v = Math.round(yuan / 1000) / 10; // 元 → 萬元，留一位小數
      if (v !== 0) {
        if (!flowMap.has(key)) flowMap.set(key, {});
        flowMap.get(key)[date] = v;
      }
    }
  }
  data.flows = [...flowMap].filter(([, days]) => Object.keys(days).length).map(([key, days]) => {
    const [stock, broker, type] = key.split('|');
    return {
      stock, broker, type, days,
    };
  });

  const cal = new Set([...(data.calendar || []), ...newDates]);
  data.calendar = [...cal].sort();
  data.latest = data.calendar[data.calendar.length - 1];

  const stocks = new Map((data.stocks || []).map((s) => [s.code, s.name]));
  for (const [c, n] of stockNames) stocks.set(c, n);
  data.stocks = [...stocks].map(([code, name]) => ({ code, name }));

  const brokers = new Map((data.brokers || []).map((b) => [b.code, b]));
  for (const [code, name] of brokerNames) {
    // 總公司代號多為末碼 0（例：1020 合庫、9800 元大），這只是近似判斷
    if (!brokers.has(code)) brokers.set(code, { code, name, hq: /0$/.test(code) });
  }
  data.brokers = [...brokers.values()];

  data.bars = data.bars || {};
  const extBars = loadBars(args.bars);
  const missingBars = [];
  for (const { code } of data.stocks) {
    data.bars[code] = { ...(data.bars[code] || {}), ...(extBars[code] || {}) };
    for (const d of newDates) {
      if (!data.bars[code][d]) {
        const h = vwapHint.get(`${code}|${d}`);
        if (h) data.bars[code][d] = [h.vwap, h.hi, h.lo, h.vwap, h.lots].map((x) => Math.round(x * 100) / 100);
        missingBars.push(`${code} ${d}${h ? '（以買賣日報表的成交價區間暫代，開收盤為均價）' : '（無資料）'}`);
      }
    }
  }
  data.source = data.source || '證交所買賣日報表';

  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, JSON.stringify(data));

  console.log(`處理 ${files} 個檔案，交易日：${[...newDates].sort().join(', ') || '無'}`);
  console.log(`輸出 ${outFile}：${data.stocks.length} 檔標的、${data.brokers.length} 個分點、${data.flows.length} 筆分點紀錄、${data.calendar.length} 個交易日`);
  if (unmapped.size) console.warn(`⚠ 對照表找不到、已略過的代號：${[...unmapped].join(', ')}`);
  if (missingBars.length) console.warn(`⚠ 缺少日K（請用 --bars 提供）：\n  ${missingBars.join('\n  ')}`);
}

main();
