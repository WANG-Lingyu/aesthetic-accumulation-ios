// 人物 AI 抠图 —— MediaPipe Selfie Segmentation。
// 模型 + WASM 全部自托管（./mediapipe/），在手机浏览器本地运行，图片不出设备、不上传。

const MAX_DIM = 1024; // 抠图输出最长边

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = src;
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error('抠图引擎加载失败: ' + src));
    document.head.appendChild(s);
  });
}

let scriptPromise = null;
function ensureMediaPipe() {
  if (window.SelfieSegmentation) return Promise.resolve(window.SelfieSegmentation);
  if (!scriptPromise) {
    scriptPromise = loadScript('./mediapipe/selfie_segmentation.js').then(() => {
      if (!window.SelfieSegmentation) throw new Error('抠图引擎初始化失败');
      return window.SelfieSegmentation;
    });
  }
  return scriptPromise;
}

export function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('图片读取失败'));
    img.src = src;
  });
}

export function downscaleCanvas(img, maxDim) {
  const w0 = img.naturalWidth || img.width;
  const h0 = img.naturalHeight || img.height;
  const scale = Math.min(1, maxDim / Math.max(w0, h0));
  const w = Math.max(1, Math.round(w0 * scale));
  const h = Math.max(1, Math.round(h0 * scale));
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  canvas.getContext('2d').drawImage(img, 0, 0, w, h);
  return canvas;
}

// 对一张图片做人物抠图，返回透明背景 PNG 的 dataURL。
// 传入 HTMLImageElement 或 dataURL 字符串均可。
export async function cutoutPerson(source) {
  const img = source instanceof HTMLImageElement ? source : await loadImage(source);
  const canvas = downscaleCanvas(img, MAX_DIM);

  const SelfieSegmentation = await ensureMediaPipe();
  const segmentation = new SelfieSegmentation({
    locateFile: (file) => './mediapipe/' + file,
  });
  segmentation.setOptions({ modelSelection: 0, selfieMode: false });

  let result = null;
  segmentation.onResults((r) => { result = r; });

  try {
    await segmentation.send({ image: canvas });
  } catch (e) {
    segmentation.close();
    throw new Error('抠图处理失败：' + (e && e.message ? e.message : e));
  }

  if (!result || !result.segmentationMask) {
    segmentation.close();
    throw new Error('未检测到人物，抠图失败');
  }

  const out = document.createElement('canvas');
  out.width = canvas.width;
  out.height = canvas.height;
  const ctx = out.getContext('2d');
  ctx.drawImage(canvas, 0, 0);
  ctx.globalCompositeOperation = 'destination-in';
  ctx.drawImage(result.segmentationMask, 0, 0, out.width, out.height);

  const png = out.toDataURL('image/png');
  segmentation.close();
  return png;
}
