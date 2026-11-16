// 本地数据层（IndexedDB）—— 所有素材数据只存在手机浏览器本地，不上传服务器。

const DB_NAME = 'aesthetic';
const DB_VERSION = 1;

let dbPromise = null;

function openDB() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains('items')) {
        db.createObjectStore('items', { keyPath: 'id' });
      }
      if (!db.objectStoreNames.contains('albums')) {
        db.createObjectStore('albums', { keyPath: 'id' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

async function getAll(store) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const rq = db.transaction(store, 'readonly').objectStore(store).getAll();
    rq.onsuccess = () => resolve(rq.result || []);
    rq.onerror = () => reject(rq.error);
  });
}

async function put(store, value) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const rq = db.transaction(store, 'readwrite').objectStore(store).put(value);
    rq.onsuccess = () => resolve(rq.result);
    rq.onerror = () => reject(rq.error);
  });
}

async function del(store, key) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const rq = db.transaction(store, 'readwrite').objectStore(store).delete(key);
    rq.onsuccess = () => resolve();
    rq.onerror = () => reject(rq.error);
  });
}

export { openDB, getAll, put, del };
