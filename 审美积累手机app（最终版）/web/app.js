import { getAll, put, del } from './db.js';
import { cutoutPerson, loadImage, downscaleCanvas } from './cutout.js';

const CATEGORIES = ['上装', '下装', '连衣裙', '外套', '鞋子', '包包', '首饰', '配饰'];

const IC = {
  material: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="8" height="8" rx="2"/><rect x="13" y="3" width="8" height="8" rx="2"/><rect x="3" y="13" width="8" height="8" rx="2"/><rect x="13" y="13" width="8" height="8" rx="2"/></svg>',
  outfit: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M9 4 7 6l-3 2 2 2 2-1v11h8V9l2 1 2-2-3-2-2-2a2 2 0 0 1-4 0Z"/></svg>',
  calendar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>',
  me: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>',
  plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>',
  back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 5l-7 7 7 7"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="18" height="18"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>',
  camera: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13" r="3.5"/></svg>',
  photo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m3 17 5-5 3 3 3-3 7 7"/></svg>',
  cutout: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="6" cy="6" r="2.6"/><circle cx="6" cy="18" r="2.6"/><path d="M8.2 7.6 20 19.4M8.2 16.4 20 4.6"/></svg>',
  folder: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/></svg>',
  star: '<svg viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1.4"><path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>',
};

const state = {
  items: [],
  albums: [],
  tab: 'material',
  albumFilter: null,   // null = 全部素材
  itemId: null,        // 当前详情
  search: '',
  sheetOpen: false,
  pendingFiles: null,
  cutout: null,        // { stage, src, result }
  modal: null,         // { title, value, onSubmit }
};

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function currentItem() { return state.items.find((i) => i.id === state.itemId) || null; }

// ---------- 存储 ----------
async function loadAll() {
  const [items, albums] = await Promise.all([getAll('items'), getAll('albums')]);
  state.items = items.sort((a, b) => b.createdAt - a.createdAt);
  state.albums = albums.sort((a, b) => a.createdAt - b.createdAt);
}
const saveTimers = {};
function scheduleSaveItem(id) {
  clearTimeout(saveTimers[id]);
  saveTimers[id] = setTimeout(() => {
    const it = state.items.find((i) => i.id === id);
    if (it) put('items', it);
  }, 400);
}
function saveItemNow(id) {
  const it = state.items.find((i) => i.id === id);
  if (it) put('items', it);
}

// ---------- 颜色 ----------
function hexToRgb(hex) {
  const h = hex.replace('#', '');
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}
function colorDist(a, b) {
  const [r1, g1, b1] = hexToRgb(a), [r2, g2, b2] = hexToRgb(b);
  return Math.sqrt((r1 - r2) ** 2 + (g1 - g2) ** 2 + (b1 - b2) ** 2);
}
function extractColors(canvas) {
  const s = 32;
  const c = document.createElement('canvas');
  c.width = s; c.height = s;
  const ctx = c.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(canvas, 0, 0, s, s);
  const data = ctx.getImageData(0, 0, s, s).data;
  const hist = new Map();
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 128) continue;
    const key = ((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4);
    hist.set(key, (hist.get(key) || 0) + 1);
  }
  const entries = [...hist.entries()].sort((a, b) => b[1] - a[1]);
  const colors = [];
  for (const [key] of entries) {
    const r = (key >> 8) & 15, g = (key >> 4) & 15, b = key & 15;
    const hex = '#' + [r, g, b].map((v) => (v * 17).toString(16).padStart(2, '0')).join('');
    if (!colors.some((cc) => colorDist(cc, hex) < 42)) colors.push(hex);
    if (colors.length >= 5) break;
  }
  return colors;
}

// ---------- 图片工具 ----------
function readAsDataURL(file) {
  return new Promise((res, rej) => {
    const fr = new FileReader();
    fr.onload = () => res(fr.result);
    fr.onerror = () => rej(new Error('读取失败'));
    fr.readAsDataURL(file);
  });
}
function baseName(name) { return (name || '').replace(/\.[^.]+$/, '') || '未命名'; }

// ---------- 导入照片 ----------
function pickImages(capture) {
  const inp = document.createElement('input');
  inp.type = 'file';
  inp.accept = 'image/*';
  inp.multiple = !capture;
  if (capture) inp.setAttribute('capture', 'environment');
  inp.onchange = () => {
    if (inp.files && inp.files.length) {
      state.pendingFiles = [...inp.files];
      render();
    }
  };
  inp.click();
}

async function importFiles(files, targetAlbum) {
  toast('正在导入…');
  let added = 0, dup = 0, fail = 0;
  for (const file of files) {
    if (!file.type.startsWith('image/')) { fail++; continue; }
    try {
      const dataUrl = await readAsDataURL(file);
      const img = await loadImage(dataUrl);
      const canvas = downscaleCanvas(img, 1600);
      const jpeg = canvas.toDataURL('image/jpeg', 0.82);
      if (state.items.some((i) => i.image === jpeg)) { dup++; continue; } // 精确查重
      const item = {
        id: uid(),
        name: baseName(file.name),
        note: '',
        category: '',
        tags: [],
        albumIds: targetAlbum ? [targetAlbum] : [],
        colors: extractColors(canvas),
        favorite: false,
        isCutout: false,
        createdAt: Date.now(),
        image: jpeg,
      };
      state.items.unshift(item);
      await put('items', item);
      added++;
    } catch (e) { fail++; }
  }
  // 若目标册子无封面，用第一张图做封面
  if (targetAlbum && added > 0) {
    const alb = state.albums.find((a) => a.id === targetAlbum);
    if (alb && !alb.coverId) {
      const first = state.items.filter((i) => (i.albumIds || []).includes(targetAlbum))[0];
      if (first) { alb.coverId = first.id; await put('albums', alb); }
    }
  }
  render();
  toast(added ? `已导入 ${added} 张${dup ? `，跳过重复 ${dup} 张` : ''}${fail ? `，失败 ${fail} 张` : ''}` : (dup ? `全部为重复照片（${dup} 张）` : '未导入任何照片'));
}

// ---------- 筛选 ----------
function filteredItems() {
  let list = state.items;
  if (state.albumFilter) list = list.filter((i) => (i.albumIds || []).includes(state.albumFilter));
  if (state.search) {
    const q = state.search.toLowerCase();
    list = list.filter((i) =>
      (i.name || '').toLowerCase().includes(q) ||
      (i.note || '').toLowerCase().includes(q) ||
      (i.category || '').toLowerCase().includes(q) ||
      (i.tags || []).some((t) => t.toLowerCase().includes(q)) ||
      state.albums.some((a) => (i.albumIds || []).includes(a.id) && a.name.toLowerCase().includes(q))
    );
  }
  return list;
}
function albumCount(id) { return state.items.filter((i) => (i.albumIds || []).includes(id)).length; }
function albumCover(album) {
  if (album.coverId) {
    const it = state.items.find((i) => i.id === album.coverId);
    if (it) return it.image;
  }
  const first = state.items.filter((i) => (i.albumIds || []).includes(album.id))[0];
  return first ? first.image : null;
}

// ---------- 渲染 ----------
function render() {
  const app = document.getElementById('app');
  app.innerHTML = viewHTML() + tabbarHTML() + detailHTML() + sheetHTML() + albumPickerHTML() + cutoutHTML() + modalHTML();
}

function viewHTML() {
  let content;
  if (state.tab === 'material') content = materialHTML();
  else if (state.tab === 'outfit') content = outfitHTML();
  else content = placeholderHTML();
  return '<div class="view" id="view">' + content + '</div>';
}

function tabbarHTML() {
  const tabs = [
    ['material', '素材', IC.material],
    ['outfit', '搭配', IC.outfit],
    ['calendar', '日历', IC.calendar],
    ['me', '我的', IC.me],
  ];
  const items = tabs.map(([key, label, ic]) =>
    `<button class="tab ${state.tab === key ? 'active' : ''}" data-action="tab-${key}">${ic}<span>${label}</span></button>`
  );
  return `<div class="tabbar">
    ${items[0]}${items[1]}
    <div class="plus-wrap"><div class="plus-btn" data-action="open-plus">${IC.plus}</div></div>
    ${items[2]}${items[3]}
  </div>`;
}

function placeholderHTML() {
  const map = {
    outfit: { ic: IC.outfit, t: '搭配', d: '抠图 → 衣橱 → 搭配画板（缩放/旋转/层级/多方案）' },
    calendar: { ic: IC.calendar, t: '日历', d: '按天记录穿搭/妆容/姿势/滤镜，复制前一天、定位+天气+建议' },
    me: { ic: IC.me, t: '我的', d: '设置、客服、AI 审美报告、数据统计（本阶段为占位）' },
  };
  const p = map[state.tab];
  return `<div class="placeholder">
    <div class="big">${p.ic.replace('<svg', '<svg width="52" height="52"')}</div>
    <h2>${p.t}</h2>
    <p>${p.d}</p>
    <p>本模块即将上线</p>
    <p style="font-size:12px;color:#c0b9ab;margin-top:22px">· 数据仅保存在本机浏览器，不上传服务器 ·</p>
  </div>`;
}

function outfitHTML() {
  return `<div class="topbar">
      <h1>搭配</h1>
      <div class="sub">抠图 · 衣橱 · 搭配画板</div>
    </div>
    <div style="padding:0 18px">
      <button class="btn primary" style="width:100%" data-action="cutout-open">${IC.cutout.replace('<svg', '<svg width="20" height="20" style="vertical-align:-5px;margin-right:6px"')}AI 抠图（人物）</button>
    </div>
    <div class="placeholder" style="padding-top:36px">
      <div class="big">🧥</div>
      <h2>衣橱 · 搭配画板</h2>
      <p>衣橱（上装/下装/连衣裙/鞋子/包包/首饰/配饰）与搭配画板即将上线</p>
    </div>`;
}

function materialHTML() {
  const alb = state.albumFilter ? state.albums.find((a) => a.id === state.albumFilter) : null;
  const title = alb ? alb.name : '审美积累';
  const sub = alb ? `${albumCount(alb.id)} 张 · 点击返回全部` : '素材册子 · 沉淀你的审美';
  return `
    <div class="topbar">
      <h1>${esc(title)}</h1>
      <div class="sub">${esc(sub)}</div>
      <div class="search-row">
        <div class="search-box">
          <span class="ic">${IC.search}</span>
          <input data-input="search" placeholder="搜索关键词 / 标签 / 分类 / 册子" value="${esc(state.search)}">
        </div>
      </div>
    </div>
    <div class="shelf">
      <div class="album-card ${state.albumFilter === null ? 'active' : ''}" data-action="all-items">
        <div class="album-cover"><span class="ph">全部</span><span class="count">${state.items.length}</span></div>
        <div class="nm">全部素材</div>
      </div>
      ${state.albums.map((a) => {
        const cv = albumCover(a);
        return `<div class="album-card ${state.albumFilter === a.id ? 'active' : ''}" data-action="open-album" data-id="${a.id}">
          <div class="album-cover">${cv ? `<img src="${cv}">` : '<span class="ph">无封面</span>'}<span class="count">${albumCount(a.id)}</span></div>
          <div class="nm">${esc(a.name)}</div>
        </div>`;
      }).join('')}
      <div class="album-card" data-action="new-album">
        <div class="album-cover"><span class="ph" style="font-size:22px">＋</span></div>
        <div class="nm">新建册子</div>
      </div>
    </div>
    ${alb ? `<div style="padding:6px 18px 0;display:flex;gap:10px">
        <button class="btn ghost" style="flex:0 0 auto;padding:8px 14px;font-size:13px" data-action="rename-album">改名</button>
        <button class="btn danger" style="flex:0 0 auto;padding:8px 14px;font-size:13px" data-action="delete-album">删除册子</button>
      </div>` : ''}
    <div id="grid-section">${gridSectionHTML()}</div>
  `;
}

function gridSectionHTML() {
  const list = filteredItems();
  if (!list.length) {
    return `<div class="empty">
      <div class="big">📷</div>
      <p>${state.items.length ? '没有匹配的照片' : '还没有素材'}</p>
      <p>点下方「＋」上传照片，或试试 AI 抠图</p>
    </div>`;
  }
  return `<div class="grid">${list.map((i) => `
    <div class="cell ${i.isCutout ? 'cutout-bg' : ''}" data-action="open-item" data-id="${i.id}">
      <img src="${i.image}" loading="lazy" alt="">
      ${i.isCutout ? '<span class="cutout-badge">抠图</span>' : ''}
      ${i.favorite ? `<span class="fav">${IC.star.replace('<svg', '<svg width="14" height="14"')}</span>` : ''}
      ${i.category ? `<span class="tag">${esc(i.category)}</span>` : ''}
    </div>`).join('')}</div>`;
}

function updateGrid() {
  const sec = document.getElementById('grid-section');
  if (sec) sec.innerHTML = gridSectionHTML();
}

function detailHTML() {
  const item = currentItem();
  if (!item) return '';
  const albList = state.albums;
  return `<div class="detail">
    <div class="detail-head">
      <div class="back" data-action="close-item">${IC.back}</div>
      <div class="title">素材详情</div>
      <div class="back" data-action="toggle-favorite" style="color:${item.favorite ? '#C9A86A' : 'inherit'}">${IC.star}</div>
    </div>
    <div class="detail-scroll">
      <div class="detail-img ${item.isCutout ? 'cutout-bg' : ''}"><img src="${item.image}" alt=""></div>
      ${item.isCutout ? '<p style="font-size:12px;color:#C9A86A;margin-top:8px">· AI 抠图 · 透明背景 PNG ·</p>' : ''}

      <div class="field">
        <div class="label">备注</div>
        <textarea class="note" data-input="note" placeholder="写点审美心得…">${esc(item.note)}</textarea>
      </div>

      <div class="field">
        <div class="label">分类</div>
        <div class="chips">
          ${CATEGORIES.map((c) => `<span class="chip ${item.category === c ? 'active' : ''}" data-action="set-category" data-value="${c}">${c}</span>`).join('')}
        </div>
      </div>

      <div class="field">
        <div class="label">标签</div>
        <div class="tags-input">
          <span id="tag-pills">${tagPillsHTML(item)}</span>
          <input data-input="tag" placeholder="添加标签，回车确认">
        </div>
      </div>

      <div class="field">
        <div class="label">色卡</div>
        <div class="swatches">${(item.colors || []).map((c) => `<span class="swatch" style="background:${c}" title="${c}"></span>`).join('')}<span class="swatch-hex">${(item.colors || []).join('  ')}</span></div>
      </div>

      <div class="field">
        <div class="label">放入册子（可多选）</div>
        <div class="chips">
          ${albList.map((a) => `<span class="chip album-chip ${(item.albumIds || []).includes(a.id) ? 'active' : ''}" data-action="toggle-album" data-id="${a.id}">${esc(a.name)}</span>`).join('') || '<span style="font-size:13px;color:#9AA3AC">暂无册子，可在下方新建</span>'}
        </div>
      </div>

      <div class="btn-row">
        <button class="btn ghost" data-action="new-album">＋ 新建册子</button>
        <button class="btn danger" data-action="delete-item">删除素材</button>
      </div>
      <div class="btn-row" style="margin-top:10px">
        <button class="btn primary" data-action="close-item">完成</button>
      </div>
    </div>
  </div>`;
}

function tagPillsHTML(item) {
  return (item.tags || []).map((t, idx) => `<span class="tag-pill">#${esc(t)}<span class="x" data-action="tag-remove" data-index="${idx}">✕</span></span>`).join('');
}
function renderTags(item) {
  const box = document.getElementById('tag-pills');
  if (box) box.innerHTML = tagPillsHTML(item);
}

function sheetHTML() {
  if (!state.sheetOpen) return '';
  return `<div class="sheet-mask" data-action="close-sheet">
    <div class="sheet">
      <div class="grab"></div>
      <div class="sheet-item" data-action="add-camera"><span class="ic">${IC.camera}</span><span>拍照上传<div class="sub">调用手机相机</div></span></div>
      <div class="sheet-item" data-action="add-gallery"><span class="ic">${IC.photo}</span><span>从相册上传<div class="sub">支持多选，自动查重</div></span></div>
    </div>
  </div>`;
}

function albumPickerHTML() {
  if (!state.pendingFiles) return '';
  return `<div class="sheet-mask" data-action="cancel-import">
    <div class="sheet">
      <div class="grab"></div>
      <h3 style="margin:4px 0 10px">添加到哪？</h3>
      <div class="sheet-item" data-action="import-none"><span class="ic">${IC.photo}</span><span>全部素材（不放入册子）</span></div>
      ${state.albums.map((a) => `<div class="sheet-item" data-action="import-album" data-id="${a.id}"><span class="ic">${IC.folder}</span><span>${esc(a.name)}<div class="sub">${albumCount(a.id)} 张</div></span></div>`).join('')}
      <div class="sheet-item" data-action="import-new-album"><span class="ic">${IC.folder}</span><span>＋ 新建册子并添加</span></div>
    </div>
  </div>`;
}

function cutoutHTML() {
  if (!state.cutout) return '';
  const c = state.cutout;
  let body = '';
  if (c.stage === 'loading') {
    body = `<div class="cutout-stage"><div class="hint"><span class="spinner" style="border-color:rgba(42,59,78,.25);border-top-color:#2A3B4E"></span><br><br>正在抠图…<br><span style="font-size:12px">首次使用需下载本地模型（约 6MB），请稍候</span></div></div>`;
  } else if (c.stage === 'done') {
    body = `<div class="cutout-stage"><img src="${c.result}" alt=""></div>
      <div class="cutout-actions">
        <button class="btn ghost" data-action="cutout-reset">换一张</button>
        <button class="btn primary" data-action="cutout-save">保存到素材</button>
      </div>`;
  } else {
    body = `<div class="cutout-stage">
        ${c.src ? `<img src="${c.src}" alt="">` : '<div class="hint">选择一张含人物的照片<br><span style="font-size:12px">建议半身/全身人像，效果最佳</span></div>'}
      </div>
      <div class="cutout-actions">
        <button class="btn ghost" data-action="cutout-pick">${c.src ? '重新选择' : '选择照片'}</button>
        ${c.src ? '<button class="btn primary" data-action="cutout-run">开始抠图</button>' : ''}
      </div>`;
  }
  return `<div class="sheet-mask" data-action="cutout-close">
    <div class="sheet">
      <div class="grab"></div>
      <h3 style="margin:4px 0 10px">AI 抠图（人物）</h3>
      <div class="cutout-body">${body}</div>
      <p style="font-size:12px;color:#9AA3AC;margin:10px 0 0">抠图在本机运行，图片不会上传。</p>
    </div>
  </div>`;
}

function modalHTML() {
  if (!state.modal) return '';
  const m = state.modal;
  return `<div class="modal-overlay">
    <div class="modal-mask" data-action="modal-cancel"></div>
    <div class="modal">
      <h3>${esc(m.title)}</h3>
      <input data-input="modal" value="${esc(m.value)}" placeholder="输入名称">
      <div class="btn-row">
        <button class="btn ghost" data-action="modal-cancel">取消</button>
        <button class="btn primary" data-action="modal-ok">确定</button>
      </div>
    </div>
  </div>`;
}

// ---------- 弹层 / 弹窗 ----------
function openModal(title, value, onSubmit) {
  state.modal = { title, value, onSubmit };
  render();
}
function openCutout() {
  state.sheetOpen = false;
  state.cutout = { stage: 'pick', src: null, result: null };
  render();
}

function toast(msg) {
  document.querySelectorAll('.toast').forEach((t) => t.remove());
  const div = document.createElement('div');
  div.className = 'toast';
  div.textContent = msg;
  document.getElementById('app').appendChild(div);
  setTimeout(() => div.remove(), 2400);
}

// ---------- 事件 ----------
async function onClick(e) {
  const t = e.target;
  const actionEl = t.closest('[data-action]');
  if (!actionEl) return;
  const action = actionEl.dataset.action;
  if ((action === 'close-sheet' || action === 'modal-cancel' || action === 'cutout-close' || action === 'cancel-import') && t !== actionEl) return;

  switch (action) {
    case 'tab-material': state.tab = 'material'; state.albumFilter = null; state.itemId = null; render(); break;
    case 'tab-outfit': case 'tab-calendar': case 'tab-me':
      state.tab = action.slice(4); state.itemId = null; render(); break;
    case 'open-plus': state.sheetOpen = true; render(); break;
    case 'close-sheet': state.sheetOpen = false; render(); break;
    case 'add-camera': state.sheetOpen = false; render(); pickImages(true); break;
    case 'add-gallery': state.sheetOpen = false; render(); pickImages(false); break;
    case 'cancel-import': state.pendingFiles = null; render(); break;
    case 'import-none': {
      const files = state.pendingFiles; state.pendingFiles = null; render();
      importFiles(files, null);
      break;
    }
    case 'import-album': {
      const files = state.pendingFiles; const id = actionEl.dataset.id;
      state.pendingFiles = null; render();
      importFiles(files, id);
      break;
    }
    case 'import-new-album': {
      const files = state.pendingFiles; state.pendingFiles = null;
      openModal('新建册子', '', async (name) => {
        const n = (name || '').trim();
        if (!n) return toast('请输入册子名称');
        const alb = { id: uid(), name: n, coverId: null, createdAt: Date.now() };
        state.albums.unshift(alb);
        await put('albums', alb);
        importFiles(files, alb.id);
      });
      break;
    }
    case 'new-album': {
      state.sheetOpen = false;
      openModal('新建册子', '', async (name) => {
        const n = (name || '').trim();
        if (!n) return toast('请输入册子名称');
        const alb = { id: uid(), name: n, coverId: null, createdAt: Date.now() };
        state.albums.unshift(alb);
        await put('albums', alb);
        render();
        toast('已新建册子');
      });
      break;
    }
    case 'all-items': state.albumFilter = null; render(); break;
    case 'open-album': state.albumFilter = actionEl.dataset.id; render(); break;
    case 'rename-album': {
      const a = state.albums.find((x) => x.id === state.albumFilter);
      if (!a) break;
      openModal('重命名册子', a.name, async (name) => {
        const n = (name || '').trim();
        if (!n) return;
        a.name = n; await put('albums', a); render();
      });
      break;
    }
    case 'delete-album': {
      const a = state.albums.find((x) => x.id === state.albumFilter);
      if (!a) break;
      if (!confirm(`删除册子「${a.name}」？照片不会被删除。`)) break;
      // 从所有素材中移除该册子
      for (const it of state.items) {
        if ((it.albumIds || []).includes(a.id)) { it.albumIds = it.albumIds.filter((x) => x !== a.id); await put('items', it); }
      }
      state.albums = state.albums.filter((x) => x.id !== a.id);
      await del('albums', a.id);
      state.albumFilter = null;
      render();
      toast('册子已删除');
      break;
    }
    case 'open-item': state.itemId = actionEl.dataset.id; render(); break;
    case 'close-item': state.itemId = null; render(); break;
    case 'set-category': {
      const item = currentItem();
      if (!item) break;
      item.category = item.category === actionEl.dataset.value ? '' : actionEl.dataset.value;
      saveItemNow(item.id); render();
      break;
    }
    case 'toggle-album': {
      const item = currentItem();
      if (!item) break;
      const id = actionEl.dataset.id;
      item.albumIds = item.albumIds || [];
      item.albumIds = item.albumIds.includes(id) ? item.albumIds.filter((x) => x !== id) : item.albumIds.concat(id);
      saveItemNow(item.id); render();
      break;
    }
    case 'toggle-favorite': {
      const item = currentItem();
      if (!item) break;
      item.favorite = !item.favorite;
      saveItemNow(item.id); render();
      break;
    }
    case 'tag-remove': {
      const item = currentItem();
      if (!item) break;
      const idx = parseInt(actionEl.dataset.index, 10);
      item.tags = (item.tags || []).filter((_, i) => i !== idx);
      saveItemNow(item.id); renderTags(item);
      break;
    }
    case 'delete-item': {
      const item = currentItem();
      if (!item) break;
      if (!confirm('确定删除这张素材？此操作不可恢复。')) break;
      state.items = state.items.filter((i) => i.id !== item.id);
      await del('items', item.id);
      // 若册子封面指向它，清空封面
      for (const a of state.albums) {
        if (a.coverId === item.id) { a.coverId = null; await put('albums', a); }
      }
      state.itemId = null;
      render();
      toast('已删除');
      break;
    }
    case 'cutout-open': openCutout(); break;
    case 'cutout-close': state.cutout = null; render(); break;
    case 'cutout-pick': {
      const inp = document.createElement('input');
      inp.type = 'file'; inp.accept = 'image/*'; inp.setAttribute('capture', 'environment');
      inp.onchange = async () => {
        const f = inp.files && inp.files[0];
        if (!f) return;
        const dataUrl = await readAsDataURL(f);
        if (state.cutout) { state.cutout.src = dataUrl; render(); }
      };
      inp.click();
      break;
    }
    case 'cutout-run': {
      if (!state.cutout.src) break;
      state.cutout.stage = 'loading';
      render();
      const src = state.cutout.src;
      cutoutPerson(src).then((png) => {
        if (!state.cutout || state.cutout.stage !== 'loading') return;
        state.cutout.stage = 'done';
        state.cutout.result = png;
        render();
      }).catch((err) => {
        if (!state.cutout) return;
        state.cutout.stage = 'pick';
        render();
        toast('抠图失败：' + (err && err.message ? err.message : err));
      });
      break;
    }
    case 'cutout-reset': state.cutout = { stage: 'pick', src: null, result: null }; render(); break;
    case 'cutout-save': {
      if (!state.cutout.result) break;
      const item = {
        id: uid(),
        name: '抠图 ' + new Date().toLocaleDateString('zh-CN'),
        note: '',
        category: '',
        tags: ['抠图'],
        albumIds: state.albumFilter ? [state.albumFilter] : [],
        colors: [],
        favorite: false,
        isCutout: true,
        createdAt: Date.now(),
        image: state.cutout.result,
      };
      state.items.unshift(item);
      await put('items', item);
      if (item.albumIds.length) {
        const alb = state.albums.find((a) => a.id === item.albumIds[0]);
        if (alb && !alb.coverId) { alb.coverId = item.id; await put('albums', alb); }
      }
      state.cutout = null;
      render();
      toast('已保存到素材');
      break;
    }
    case 'modal-cancel': state.modal = null; render(); break;
    case 'modal-ok': {
      const m = state.modal;
      const input = document.querySelector('[data-input="modal"]');
      const val = input ? input.value : '';
      state.modal = null;
      render();
      if (m && m.onSubmit) m.onSubmit(val);
      break;
    }
  }
}

function onInput(e) {
  const el = e.target;
  if (el.matches('[data-input="search"]')) {
    state.search = el.value;
    updateGrid();
  } else if (el.matches('[data-input="note"]')) {
    const item = currentItem();
    if (item) { item.note = el.value; scheduleSaveItem(item.id); }
  }
}

function onKeydown(e) {
  const el = e.target;
  if (el.matches('[data-input="tag"]') && e.key === 'Enter') {
    e.preventDefault();
    const val = el.value.trim();
    const item = currentItem();
    if (!item) return;
    if (val && !(item.tags || []).includes(val)) {
      item.tags = item.tags || [];
      item.tags.push(val);
      saveItemNow(item.id);
      renderTags(item);
    }
    el.value = '';
  } else if (el.matches('[data-input="modal"]') && e.key === 'Enter') {
    e.preventDefault();
    document.querySelector('[data-action="modal-ok"]')?.click();
  } else if (e.key === 'Escape') {
    if (state.modal) { state.modal = null; render(); }
    else if (state.cutout) { state.cutout = null; render(); }
    else if (state.sheetOpen) { state.sheetOpen = false; render(); }
  }
}

function registerSW() {
  if ('serviceWorker' in navigator && location.protocol === 'https:') {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  }
}

async function init() {
  await loadAll();
  const app = document.getElementById('app');
  app.addEventListener('click', onClick);
  app.addEventListener('input', onInput);
  app.addEventListener('keydown', onKeydown);
  registerSW();
  render();
}

init();
