const video = document.querySelector("#camera");
const canvas = document.querySelector("#paint");
const cameraButton = document.querySelector("#cameraButton");
const undoButton = document.querySelector("#undoButton");
const clearButton = document.querySelector("#clearButton");
const widthControl = document.querySelector("#widthControl");
const statusOutput = document.querySelector("#status");

const context = canvas.getContext("2d", { alpha: true });
const patchCanvas = document.createElement("canvas");
const patchContext = patchCanvas.getContext("2d", { willReadFrequently: true });

const sectionResolution = 128;
const sliceSpacing = 0.75;
const sliceOverlap = 0.35;
const maximumSlicesPerSegment = 140;
const minimumPointDistance = 3;
const minimumAngleDelta = Math.PI / 90;

let strokes = [];
let activeSamples = [];
let isDrawing = false;
let currentBrushAngle = 0;
let dpr = window.devicePixelRatio || 1;

function resizeCanvas() {
  dpr = window.devicePixelRatio || 1;
  const width = window.innerWidth;
  const height = window.innerHeight;
  canvas.width = Math.max(1, Math.round(width * dpr));
  canvas.height = Math.max(1, Math.round(height * dpr));
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  redraw();
}

async function startCamera() {
  if (!navigator.mediaDevices?.getUserMedia) {
    statusOutput.value = "Camera API is unavailable in this browser.";
    return;
  }

  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: { ideal: "environment" },
        width: { ideal: 1280 },
        height: { ideal: 720 }
      }
    });
    video.srcObject = stream;
    await video.play();
    statusOutput.value = "";
  } catch (error) {
    statusOutput.value = error instanceof Error ? error.message : "Camera permission failed.";
  }
}

function beginStroke(event) {
  if (!isCameraReady()) {
    startCamera();
    return;
  }

  const point = pointerPoint(event);
  isDrawing = true;
  activeSamples = [];
  canvas.setPointerCapture(event.pointerId);
  appendSample(point, performance.now(), true);
  redraw();
}

function moveStroke(event) {
  if (!isDrawing) {
    return;
  }

  const point = pointerPoint(event);
  appendSample(point, performance.now(), false);
  redraw();
}

function endStroke(event) {
  if (!isDrawing) {
    return;
  }

  appendSample(pointerPoint(event), performance.now(), false);
  if (activeSamples.length > 0) {
    strokes.push(activeSamples);
  }
  activeSamples = [];
  isDrawing = false;
  redraw();
}

function cancelStroke() {
  if (activeSamples.length > 0) {
    strokes.push(activeSamples);
  }
  activeSamples = [];
  isDrawing = false;
  redraw();
}

function appendSample(point, timestamp, force) {
  const brushWidth = Number(widthControl.value);
  const previous = activeSamples.at(-1);
  const angle = previous ? brushAngle(previous, point, currentBrushAngle) : currentBrushAngle;
  currentBrushAngle = angle;

  if (!force && previous && !shouldAppend(previous, point, brushWidth, angle)) {
    return;
  }

  const section = captureSection(point, angle, brushWidth);
  activeSamples.push({
    nx: point.x / window.innerWidth,
    ny: point.y / window.innerHeight,
    width: brushWidth,
    angle,
    timestamp,
    section
  });
}

function shouldAppend(previous, point, width, angle) {
  const previousPoint = samplePoint(previous);
  const dx = point.x - previousPoint.x;
  const dy = point.y - previousPoint.y;
  const distance = Math.hypot(dx, dy);
  const widthDelta = Math.abs(width - previous.width);
  const angleDelta = angularDistance(angle, previous.angle);
  return distance >= minimumPointDistance || widthDelta >= 1 || angleDelta >= minimumAngleDelta;
}

function captureSection(point, angle, brushWidth) {
  const mapping = screenToVideo(point);
  if (!mapping) {
    return null;
  }

  const cross = crossVector(angle);
  const lineLength = Math.max(2, brushWidth * mapping.scale);
  const halfLength = lineLength / 2;
  const padding = 3;
  const start = {
    x: mapping.x - cross.x * halfLength,
    y: mapping.y - cross.y * halfLength
  };
  const end = {
    x: mapping.x + cross.x * halfLength,
    y: mapping.y + cross.y * halfLength
  };
  const bounds = clampBounds({
    x: Math.min(start.x, end.x) - padding,
    y: Math.min(start.y, end.y) - padding,
    width: Math.abs(end.x - start.x) + padding * 2,
    height: Math.abs(end.y - start.y) + padding * 2
  });

  if (bounds.width <= 0 || bounds.height <= 0) {
    return null;
  }

  patchCanvas.width = Math.max(1, Math.ceil(bounds.width));
  patchCanvas.height = Math.max(1, Math.ceil(bounds.height));
  patchContext.setTransform(1, 0, 0, 1, 0, 0);
  patchContext.clearRect(0, 0, patchCanvas.width, patchCanvas.height);
  patchContext.drawImage(
    video,
    bounds.x,
    bounds.y,
    bounds.width,
    bounds.height,
    0,
    0,
    patchCanvas.width,
    patchCanvas.height
  );

  const patch = patchContext.getImageData(0, 0, patchCanvas.width, patchCanvas.height);
  const patchScaleX = patchCanvas.width / bounds.width;
  const patchScaleY = patchCanvas.height / bounds.height;
  const sectionCanvas = document.createElement("canvas");
  sectionCanvas.width = 1;
  sectionCanvas.height = sectionResolution;
  const sectionContext = sectionCanvas.getContext("2d");
  const section = sectionContext.createImageData(1, sectionResolution);

  for (let row = 0; row < sectionResolution; row += 1) {
    const ratio = sectionResolution === 1 ? 0.5 : row / (sectionResolution - 1);
    const offset = (ratio - 0.5) * lineLength;
    const sampleX = (mapping.x + cross.x * offset - bounds.x) * patchScaleX;
    const sampleY = (mapping.y + cross.y * offset - bounds.y) * patchScaleY;
    const color = sampleBilinear(patch, sampleX, sampleY);
    const index = row * 4;
    section.data[index] = color.r;
    section.data[index + 1] = color.g;
    section.data[index + 2] = color.b;
    section.data[index + 3] = 255;
  }

  sectionContext.putImageData(section, 0, 0);
  return sectionCanvas;
}

function redraw() {
  const width = window.innerWidth;
  const height = window.innerHeight;
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  context.clearRect(0, 0, width, height);
  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = "high";

  for (const stroke of strokes) {
    drawStroke(stroke);
  }
  if (activeSamples.length > 0) {
    drawStroke(activeSamples);
  }

  undoButton.disabled = strokes.length === 0;
  clearButton.disabled = strokes.length === 0 && activeSamples.length === 0;
}

function drawStroke(samples) {
  if (samples.length < 2) {
    return;
  }

  for (let index = 1; index < samples.length; index += 1) {
    drawSegment(samples[index - 1], samples[index]);
  }
}

function drawSegment(previous, current) {
  const start = samplePoint(previous);
  const end = samplePoint(current);
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const length = Math.hypot(dx, dy);

  if (length <= 0.001 || (!previous.section && !current.section)) {
    return;
  }

  const tangent = { x: dx / length, y: dy / length };
  const sliceCount = Math.min(maximumSlicesPerSegment, Math.max(1, Math.ceil(length / sliceSpacing)));
  const thickness = length / sliceCount + sliceOverlap;

  for (let index = 0; index <= sliceCount; index += 1) {
    const t = index / sliceCount;
    const center = {
      x: start.x + dx * t,
      y: start.y + dy * t
    };
    const width = interpolate(previous.width, current.width, t);
    const angle = interpolateAngle(previous.angle, current.angle, t);
    const cross = crossVector(angle);
    drawSlice(center, tangent, cross, thickness, width, t, previous.section, current.section);
  }
}

function drawSlice(center, tangent, cross, thickness, width, t, previousSection, currentSection) {
  context.save();
  context.transform(
    tangent.x * thickness,
    tangent.y * thickness,
    cross.x * width,
    cross.y * width,
    center.x,
    center.y
  );

  if (previousSection) {
    context.globalAlpha = 1;
    context.drawImage(previousSection, -0.5, -0.5, 1, 1);
  }
  if (currentSection) {
    context.globalAlpha = Math.min(1, t);
    context.drawImage(currentSection, -0.5, -0.5, 1, 1);
  }

  context.restore();
}

function screenToVideo(point) {
  const videoWidth = video.videoWidth;
  const videoHeight = video.videoHeight;
  const viewWidth = window.innerWidth;
  const viewHeight = window.innerHeight;

  if (!videoWidth || !videoHeight || !viewWidth || !viewHeight) {
    return null;
  }

  const scale = Math.max(viewWidth / videoWidth, viewHeight / videoHeight);
  const visibleWidth = viewWidth / scale;
  const visibleHeight = viewHeight / scale;
  const offsetX = (videoWidth - visibleWidth) / 2;
  const offsetY = (videoHeight - visibleHeight) / 2;

  return {
    x: offsetX + point.x / scale,
    y: offsetY + point.y / scale,
    scale: 1 / scale
  };
}

function clampBounds(bounds) {
  const x = clamp(bounds.x, 0, video.videoWidth);
  const y = clamp(bounds.y, 0, video.videoHeight);
  const maxX = clamp(bounds.x + bounds.width, 0, video.videoWidth);
  const maxY = clamp(bounds.y + bounds.height, 0, video.videoHeight);
  return {
    x,
    y,
    width: Math.max(0, maxX - x),
    height: Math.max(0, maxY - y)
  };
}

function sampleBilinear(image, x, y) {
  const clampedX = clamp(x, 0, image.width - 1);
  const clampedY = clamp(y, 0, image.height - 1);
  const x0 = Math.floor(clampedX);
  const y0 = Math.floor(clampedY);
  const x1 = Math.min(image.width - 1, x0 + 1);
  const y1 = Math.min(image.height - 1, y0 + 1);
  const tx = clampedX - x0;
  const ty = clampedY - y0;
  const c00 = pixel(image, x0, y0);
  const c10 = pixel(image, x1, y0);
  const c01 = pixel(image, x0, y1);
  const c11 = pixel(image, x1, y1);

  return {
    r: mix(mix(c00.r, c10.r, tx), mix(c01.r, c11.r, tx), ty),
    g: mix(mix(c00.g, c10.g, tx), mix(c01.g, c11.g, tx), ty),
    b: mix(mix(c00.b, c10.b, tx), mix(c01.b, c11.b, tx), ty)
  };
}

function pixel(image, x, y) {
  const index = (y * image.width + x) * 4;
  return {
    r: image.data[index],
    g: image.data[index + 1],
    b: image.data[index + 2]
  };
}

function pointerPoint(event) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top
  };
}

function samplePoint(sample) {
  return {
    x: sample.nx * window.innerWidth,
    y: sample.ny * window.innerHeight
  };
}

function brushAngle(start, end, fallback) {
  const startPoint = samplePoint(start);
  const dx = end.x - startPoint.x;
  const dy = end.y - startPoint.y;
  const length = Math.hypot(dx, dy);

  if (length <= 0.001) {
    return fallback;
  }

  return normalizedAngle(Math.atan2(dx / length, dy / length));
}

function crossVector(angle) {
  return {
    x: -Math.cos(angle),
    y: Math.sin(angle)
  };
}

function angularDistance(left, right) {
  const difference = Math.abs(left - right) % (Math.PI * 2);
  return Math.min(difference, Math.PI * 2 - difference);
}

function interpolate(start, end, t) {
  return start + (end - start) * t;
}

function interpolateAngle(start, end, t) {
  const delta = Math.atan2(Math.sin(end - start), Math.cos(end - start));
  return start + delta * t;
}

function normalizedAngle(angle) {
  const fullTurn = Math.PI * 2;
  const normalized = angle % fullTurn;
  return normalized >= 0 ? normalized : normalized + fullTurn;
}

function isCameraReady() {
  return video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA && video.videoWidth > 0;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function mix(start, end, t) {
  return Math.round(start + (end - start) * t);
}

cameraButton.addEventListener("click", startCamera);
undoButton.addEventListener("click", () => {
  strokes.pop();
  redraw();
});
clearButton.addEventListener("click", () => {
  strokes = [];
  activeSamples = [];
  redraw();
});
widthControl.addEventListener("input", () => {
  if (!isDrawing) {
    return;
  }
  const previous = activeSamples.at(-1);
  if (previous) {
    appendSample(samplePoint(previous), performance.now(), true);
    redraw();
  }
});

canvas.addEventListener("pointerdown", beginStroke);
canvas.addEventListener("pointermove", moveStroke);
canvas.addEventListener("pointerup", endStroke);
canvas.addEventListener("pointercancel", cancelStroke);
canvas.addEventListener("pointerleave", event => {
  if (isDrawing && event.buttons === 0) {
    cancelStroke();
  }
});

window.addEventListener("resize", resizeCanvas);
resizeCanvas();
redraw();
startCamera();
