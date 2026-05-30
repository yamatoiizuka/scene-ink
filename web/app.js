const video = document.querySelector("#camera");
const canvas = document.querySelector("#paint");
const stage = document.querySelector(".stage");
const cameraButton = document.querySelector("#cameraButton");
const undoButton = document.querySelector("#undoButton");
const clearButton = document.querySelector("#clearButton");
const widthControl = document.querySelector("#widthControl");
const statusOutput = document.querySelector("#status");

const context = canvas.getContext("2d", { alpha: true, desynchronized: true });
const committedCanvas = document.createElement("canvas");
const committedContext = committedCanvas.getContext("2d", { alpha: true, desynchronized: true });
const textureCanvas = document.createElement("canvas");
const textureContext = textureCanvas.getContext("2d", { alpha: true });
const maskCanvas = document.createElement("canvas");
const maskContext = maskCanvas.getContext("2d", { alpha: true });
const strokeTextureCanvas = document.createElement("canvas");
const strokeTextureContext = strokeTextureCanvas.getContext("2d", { alpha: true });

const sectionResolution = 128;
const sectionSampleWidth = 2;
const maximumRibbonSegmentLength = 8;
const tangentSmoothing = 0.58;
const textureColumnBleed = 0.18;
const ribbonOverdraw = 0.75;
const triangleClipBleed = 0.9;
const minimumPointDistance = 4.5;
const minimumAngleDelta = Math.PI / 90;
const temporalJoinRadius = 5;
const temporalJoinColumnStep = 3;
const temporalJoinMaxColumns = 20;

let strokes = [];
let activeSamples = [];
let isDrawing = false;
let currentBrushAngle = 0;
let dpr = window.devicePixelRatio || 1;
let committedStrokeCount = 0;
let committedNeedsRebuild = true;
let redrawFrame = 0;

function resizeCanvas() {
  dpr = window.devicePixelRatio || 1;
  const width = window.innerWidth;
  const height = window.innerHeight;
  canvas.width = Math.max(1, Math.round(width * dpr));
  canvas.height = Math.max(1, Math.round(height * dpr));
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  resizeWorkCanvas(committedCanvas, committedContext, width, height);
  resizeWorkCanvas(textureCanvas, textureContext, width, height);
  resizeWorkCanvas(maskCanvas, maskContext, width, height);
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  resetCommittedStrokes();
  redraw();
}

function resizeWorkCanvas(targetCanvas, targetContext, width, height) {
  targetCanvas.width = Math.max(1, Math.round(width * dpr));
  targetCanvas.height = Math.max(1, Math.round(height * dpr));
  targetContext.setTransform(dpr, 0, 0, dpr, 0, 0);
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
  setDrawingState(true);
  activeSamples = [];
  canvas.setPointerCapture(event.pointerId);
  appendSample(point, performance.now(), true);
  redraw();
}

function moveStroke(event) {
  if (!isDrawing) {
    return;
  }

  const events = coalescedPointerEvents(event);
  for (const pointerEvent of events) {
    appendSample(pointerPoint(pointerEvent), pointerEvent.timeStamp || performance.now(), false);
  }
  scheduleRedraw();
}

function endStroke(event) {
  if (!isDrawing) {
    return;
  }

  appendSample(pointerPoint(event), performance.now(), false);
  if (activeSamples.length > 0) {
    const stroke = activeSamples;
    strokes.push(stroke);
    activeSamples = [];
    commitStrokeIfPossible(stroke);
  } else {
    activeSamples = [];
  }
  setDrawingState(false);
  redraw();
}

function cancelStroke() {
  if (activeSamples.length > 0) {
    const stroke = activeSamples;
    strokes.push(stroke);
    commitStrokeIfPossible(stroke);
  }
  activeSamples = [];
  setDrawingState(false);
  redraw();
}

function setDrawingState(nextIsDrawing) {
  isDrawing = nextIsDrawing;
  stage.classList.toggle("is-drawing", nextIsDrawing);
}

function coalescedPointerEvents(event) {
  if (typeof event.getCoalescedEvents !== "function") {
    return [event];
  }

  const events = event.getCoalescedEvents();
  return events.length > 0 ? events : [event];
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
  if (previous && canJoinTemporalSample(previous, point, brushWidth)) {
    joinTemporalSample(previous, point, brushWidth, angle, timestamp, section);
    return;
  }

  activeSamples.push({
    nx: point.x / window.innerWidth,
    ny: point.y / window.innerHeight,
    width: brushWidth,
    angle,
    timestamp,
    joinCount: 1,
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

function canJoinTemporalSample(previous, point, width) {
  const previousPoint = samplePoint(previous);
  const radius = Math.min(
    temporalJoinRadius,
    Math.max(3, Math.min(previous.width, width) * 0.14)
  );
  return distance(previousPoint, point) <= radius;
}

function joinTemporalSample(previous, point, width, angle, timestamp, section) {
  const joinCount = (previous.joinCount || 1) + 1;
  const weight = 1 / joinCount;

  previous.nx = interpolate(previous.nx, point.x / window.innerWidth, weight);
  previous.ny = interpolate(previous.ny, point.y / window.innerHeight, weight);
  previous.width = interpolate(previous.width, width, weight);
  previous.angle = angle;
  previous.timestamp = timestamp;
  previous.section = joinTemporalSections(previous.section, section, joinCount);
  previous.joinCount = joinCount;
}

function joinTemporalSections(previousSection, nextSection, joinCount) {
  if (!previousSection) {
    return nextSection;
  }
  if (!nextSection) {
    return previousSection;
  }

  const joinedCanvas = document.createElement("canvas");
  joinedCanvas.width = Math.min(
    temporalJoinMaxColumns,
    sectionSampleWidth + Math.max(1, joinCount - 1) * temporalJoinColumnStep
  );
  joinedCanvas.height = sectionResolution;

  const joinedContext = joinedCanvas.getContext("2d");
  joinedContext.imageSmoothingEnabled = true;
  joinedContext.imageSmoothingQuality = "high";

  const lastIntervalStart = Math.max(0, 1 - 1 / Math.max(1, joinCount - 1));
  for (let column = 0; column < joinedCanvas.width; column += 1) {
    const progress = joinedCanvas.width === 1 ? 1 : column / (joinedCanvas.width - 1);
    const localT = lastIntervalStart >= 1
      ? 1
      : clamp01((progress - lastIntervalStart) / (1 - lastIntervalStart));

    if (localT < 1) {
      const previousX = Math.min(
        previousSection.width - 1,
        (lastIntervalStart <= 0 ? 0 : progress / lastIntervalStart) * (previousSection.width - 1)
      );
      joinedContext.globalAlpha = 1;
      joinedContext.drawImage(
        previousSection,
        previousX,
        0,
        1,
        previousSection.height,
        column,
        0,
        1,
        joinedCanvas.height
      );
    }

    if (localT > 0) {
      joinedContext.globalAlpha = localT;
      joinedContext.drawImage(
        nextSection,
        0,
        0,
        nextSection.width,
        nextSection.height,
        column,
        0,
        1,
        joinedCanvas.height
      );
    }
  }

  joinedContext.globalAlpha = 1;
  return joinedCanvas;
}

function captureSection(point, angle, brushWidth) {
  const mapping = screenToVideo(point);
  if (!mapping) {
    return null;
  }

  const cross = crossVector(angle);
  const tangent = { x: cross.y, y: -cross.x };
  const lineLength = Math.max(2, brushWidth * mapping.scale);
  const lineScale = sectionResolution / lineLength;
  const sectionCanvas = document.createElement("canvas");
  sectionCanvas.width = sectionSampleWidth;
  sectionCanvas.height = sectionResolution;
  const sectionContext = sectionCanvas.getContext("2d");

  sectionContext.imageSmoothingEnabled = true;
  sectionContext.imageSmoothingQuality = "high";
  sectionContext.setTransform(
    tangent.x,
    cross.x * lineScale,
    tangent.y,
    cross.y * lineScale,
    sectionSampleWidth / 2 - tangent.x * mapping.x - tangent.y * mapping.y,
    sectionResolution / 2 - (cross.x * mapping.x + cross.y * mapping.y) * lineScale
  );
  sectionContext.drawImage(video, 0, 0);
  return sectionCanvas;
}

function redraw() {
  const width = window.innerWidth;
  const height = window.innerHeight;
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  context.clearRect(0, 0, width, height);
  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = "high";

  ensureCommittedStrokes();
  context.save();
  context.setTransform(1, 0, 0, 1, 0, 0);
  context.drawImage(committedCanvas, 0, 0);
  context.restore();

  if (activeSamples.length > 0) {
    drawStrokeTo(activeSamples, context);
  }

  undoButton.disabled = strokes.length === 0;
  clearButton.disabled = strokes.length === 0 && activeSamples.length === 0;
}

function scheduleRedraw() {
  if (redrawFrame !== 0) {
    return;
  }

  redrawFrame = requestAnimationFrame(() => {
    redrawFrame = 0;
    redraw();
  });
}

function ensureCommittedStrokes() {
  if (!committedNeedsRebuild && committedStrokeCount === strokes.length) {
    return;
  }

  clearWorkCanvas(committedContext);
  committedStrokeCount = 0;
  for (const stroke of strokes) {
    drawStrokeTo(stroke, committedContext);
    committedStrokeCount += 1;
  }
  committedNeedsRebuild = false;
}

function commitStrokeIfPossible(stroke) {
  if (committedNeedsRebuild || committedStrokeCount !== strokes.length - 1) {
    committedNeedsRebuild = true;
    return;
  }

  drawStrokeTo(stroke, committedContext);
  committedStrokeCount = strokes.length;
}

function resetCommittedStrokes() {
  committedStrokeCount = 0;
  committedNeedsRebuild = true;
}

function drawStrokeTo(samples, destinationContext) {
  if (samples.length < 2) {
    return;
  }

  const renderSamples = buildRibbonSamples(samples);
  if (renderSamples.length < 2) {
    return;
  }

  const strokeTexture = buildStrokeTexture(renderSamples);
  drawTexturedStroke(renderSamples, strokeTexture);
  maskTexturedStroke(renderSamples);
  destinationContext.save();
  destinationContext.setTransform(1, 0, 0, 1, 0, 0);
  destinationContext.drawImage(textureCanvas, 0, 0);
  destinationContext.restore();
}

function drawTexturedStroke(renderSamples, strokeTexture) {
  clearWorkCanvas(textureContext);
  textureContext.imageSmoothingEnabled = true;
  textureContext.imageSmoothingQuality = "high";

  for (let index = 1; index < renderSamples.length; index += 1) {
    const previous = renderSamples[index - 1];
    const current = renderSamples[index];
    if (distance(previous, current) <= 0.001) {
      continue;
    }

    drawRibbonSegment(
      textureContext,
      strokeTexture,
      index - 1,
      index,
      ribbonFrame(previous),
      ribbonFrame(current)
    );
  }
}

function maskTexturedStroke(renderSamples) {
  clearWorkCanvas(maskContext);
  maskContext.save();
  maskContext.lineCap = "round";
  maskContext.lineJoin = "round";
  maskContext.strokeStyle = "white";
  drawWidthAwareMaskPath(renderSamples);

  maskContext.restore();

  textureContext.save();
  textureContext.setTransform(1, 0, 0, 1, 0, 0);
  textureContext.globalCompositeOperation = "destination-in";
  textureContext.drawImage(maskCanvas, 0, 0);
  textureContext.restore();
}

function drawWidthAwareMaskPath(renderSamples) {
  let startIndex = 0;
  let widthSum = renderSamples[0].width;
  let widthCount = 1;

  for (let index = 1; index < renderSamples.length; index += 1) {
    const previous = renderSamples[index - 1];
    const current = renderSamples[index];
    const widthChanged = Math.abs(current.width - previous.width) > 2;

    if (widthChanged && index - startIndex > 1) {
      strokeMaskPath(renderSamples, startIndex, index, widthSum / widthCount);
      startIndex = index - 1;
      widthSum = previous.width + current.width;
      widthCount = 2;
      continue;
    }

    widthSum += current.width;
    widthCount += 1;
  }

  strokeMaskPath(renderSamples, startIndex, renderSamples.length - 1, widthSum / widthCount);
}

function strokeMaskPath(renderSamples, startIndex, endIndex, width) {
  if (endIndex <= startIndex) {
    return;
  }

  maskContext.lineWidth = width + 1.5;
  maskContext.beginPath();
  traceSmoothPath(maskContext, renderSamples, startIndex, endIndex);
  maskContext.stroke();
}

function traceSmoothPath(targetContext, points, startIndex, endIndex) {
  const first = points[startIndex];
  targetContext.moveTo(first.x, first.y);

  for (let index = startIndex + 1; index < endIndex; index += 1) {
    targetContext.lineTo(points[index].x, points[index].y);
  }

  const last = points[endIndex];
  targetContext.lineTo(last.x, last.y);
}

function clearWorkCanvas(targetContext) {
  targetContext.save();
  targetContext.setTransform(1, 0, 0, 1, 0, 0);
  targetContext.clearRect(0, 0, targetContext.canvas.width, targetContext.canvas.height);
  targetContext.restore();
}

function buildStrokeTexture(renderSamples) {
  strokeTextureCanvas.width = Math.max(2, renderSamples.length);
  strokeTextureCanvas.height = sectionResolution;
  strokeTextureContext.setTransform(1, 0, 0, 1, 0, 0);
  strokeTextureContext.clearRect(0, 0, strokeTextureCanvas.width, strokeTextureCanvas.height);
  strokeTextureContext.imageSmoothingEnabled = true;
  strokeTextureContext.imageSmoothingQuality = "high";

  for (let column = 0; column < renderSamples.length; column += 1) {
    const previous = renderSamples[Math.max(0, column - 1)];
    const current = renderSamples[column];
    const next = renderSamples[Math.min(renderSamples.length - 1, column + 1)];
    drawResolvedTextureColumn(strokeTextureContext, current, column, 1);
    drawResolvedTextureColumn(strokeTextureContext, previous, column, textureColumnBleed);
    drawResolvedTextureColumn(strokeTextureContext, next, column, textureColumnBleed);
  }

  strokeTextureContext.globalAlpha = 1;
  return strokeTextureCanvas;
}

function drawResolvedTextureColumn(targetContext, sample, column, alpha) {
  if (!sample || alpha <= 0) {
    return;
  }

  if (sample.previousSection && sample.currentSection) {
    drawTextureColumn(targetContext, sample.previousSection, column, sample.sectionT, alpha);
    drawTextureColumn(targetContext, sample.currentSection, column, sample.sectionT, alpha * sample.sectionT);
    return;
  }

  drawTextureColumn(targetContext, sample.section, column, sample.sourceT ?? 0.5, alpha);
}

function drawTextureColumn(targetContext, section, column, sourceT, alpha) {
  if (!section || alpha <= 0) {
    return;
  }

  const sourceX = Math.min(section.width - 1, Math.max(0, sourceT * (section.width - 1)));
  targetContext.globalAlpha = alpha;
  targetContext.drawImage(
    section,
    sourceX,
    0,
    1,
    section.height,
    column,
    0,
    1,
    strokeTextureCanvas.height
  );
}

function ribbonFrame(sample) {
  const tangent = sample.tangent || { x: 1, y: 0 };
  const cross = { x: -tangent.y, y: tangent.x };
  const halfWidth = sample.width / 2 + ribbonOverdraw;

  return {
    top: {
      x: sample.x - cross.x * halfWidth,
      y: sample.y - cross.y * halfWidth
    },
    bottom: {
      x: sample.x + cross.x * halfWidth,
      y: sample.y + cross.y * halfWidth
    }
  };
}

function drawRibbonSegment(targetContext, texture, previousIndex, currentIndex, previousFrame, currentFrame) {
  drawTextureTriangle(
    targetContext,
    texture,
    previousFrame.top,
    currentFrame.top,
    previousFrame.bottom,
    firstRibbonTriangleMatrix(texture, previousIndex, currentIndex, previousFrame, currentFrame)
  );
  drawTextureTriangle(
    targetContext,
    texture,
    previousFrame.bottom,
    currentFrame.top,
    currentFrame.bottom,
    secondRibbonTriangleMatrix(texture, previousIndex, currentIndex, previousFrame, currentFrame)
  );
}

function drawTextureTriangle(targetContext, texture, p0, p1, p2, matrix) {
  if (!matrix) {
    return;
  }

  const clip = expandedTriangle(p0, p1, p2, triangleClipBleed);
  targetContext.save();
  targetContext.beginPath();
  targetContext.moveTo(clip[0].x, clip[0].y);
  targetContext.lineTo(clip[1].x, clip[1].y);
  targetContext.lineTo(clip[2].x, clip[2].y);
  targetContext.closePath();
  targetContext.clip();
  targetContext.transform(matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f);
  targetContext.drawImage(texture, 0, 0);
  targetContext.restore();
}

function expandedTriangle(p0, p1, p2, amount) {
  const center = {
    x: (p0.x + p1.x + p2.x) / 3,
    y: (p0.y + p1.y + p2.y) / 3
  };

  return [
    expandPointFromCenter(p0, center, amount),
    expandPointFromCenter(p1, center, amount),
    expandPointFromCenter(p2, center, amount)
  ];
}

function expandPointFromCenter(point, center, amount) {
  const dx = point.x - center.x;
  const dy = point.y - center.y;
  const length = Math.hypot(dx, dy);

  if (length <= 0.0001) {
    return point;
  }

  const scale = (length + amount) / length;
  return {
    x: center.x + dx * scale,
    y: center.y + dy * scale
  };
}

function firstRibbonTriangleMatrix(texture, previousIndex, currentIndex, previousFrame, currentFrame) {
  const width = currentIndex - previousIndex;
  const height = texture.height;
  if (width <= 0 || height <= 0) {
    return null;
  }

  const a = (currentFrame.top.x - previousFrame.top.x) / width;
  const b = (currentFrame.top.y - previousFrame.top.y) / width;
  const c = (previousFrame.bottom.x - previousFrame.top.x) / height;
  const d = (previousFrame.bottom.y - previousFrame.top.y) / height;

  return {
    a,
    b,
    c,
    d,
    e: previousFrame.top.x - a * previousIndex,
    f: previousFrame.top.y - b * previousIndex
  };
}

function secondRibbonTriangleMatrix(texture, previousIndex, currentIndex, previousFrame, currentFrame) {
  const width = currentIndex - previousIndex;
  const height = texture.height;
  if (width <= 0 || height <= 0) {
    return null;
  }

  const c = (currentFrame.bottom.x - currentFrame.top.x) / height;
  const d = (currentFrame.bottom.y - currentFrame.top.y) / height;
  const a = (currentFrame.bottom.x - previousFrame.bottom.x) / width;
  const b = (currentFrame.bottom.y - previousFrame.bottom.y) / width;

  return {
    a,
    b,
    c,
    d,
    e: currentFrame.top.x - a * currentIndex,
    f: currentFrame.top.y - b * currentIndex
  };
}

function buildRibbonSamples(samples) {
  const nodes = samples.map(sample => {
    const point = samplePoint(sample);
    return {
      x: point.x,
      y: point.y,
      width: sample.width,
      section: sample.section
    };
  });

  smoothRibbonPoints(nodes);
  assignRibbonTangents(nodes);
  return splitLongRibbonSegments(nodes);
}

function smoothRibbonPoints(nodes) {
  if (nodes.length < 3) {
    return;
  }

  for (let index = 1; index < nodes.length - 1; index += 1) {
    const previous = nodes[index - 1];
    const current = nodes[index];
    const next = nodes[index + 1];
    current.x = interpolate(current.x, (previous.x + next.x) / 2, tangentSmoothing);
    current.y = interpolate(current.y, (previous.y + next.y) / 2, tangentSmoothing);
  }
}

function assignRibbonTangents(nodes) {
  let fallback = { x: 1, y: 0 };

  for (let index = 0; index < nodes.length; index += 1) {
    const previous = nodes[Math.max(0, index - 1)];
    const next = nodes[Math.min(nodes.length - 1, index + 1)];
    const tangent = normalizedVector(previous, next);
    if (distance(previous, next) > 0.001) {
      fallback = tangent;
    }
    nodes[index].tangent = fallback;
  }
}

function splitLongRibbonSegments(nodes) {
  const renderSamples = [];

  for (let index = 0; index < nodes.length - 1; index += 1) {
    const start = nodes[index];
    const end = nodes[index + 1];
    const steps = Math.max(1, Math.ceil(distance(start, end) / maximumRibbonSegmentLength));
    if (index === 0) {
      renderSamples.push({ ...start });
    }

    for (let step = 1; step <= steps; step += 1) {
      const t = step / steps;
      renderSamples.push(interpolateRibbonNode(start, end, t));
    }
  }

  return renderSamples;
}

function interpolateRibbonNode(start, end, t) {
  const tangent = normalizeInterpolatedTangent(start.tangent, end.tangent, t);

  return {
    x: interpolate(start.x, end.x, t),
    y: interpolate(start.y, end.y, t),
    width: interpolate(start.width, end.width, t),
    tangent,
    previousSection: start.section,
    currentSection: end.section,
    sectionT: t,
    sourceT: t
  };
}

function normalizeInterpolatedTangent(start, end, t) {
  const x = interpolate(start?.x || 1, end?.x || 1, t);
  const y = interpolate(start?.y || 0, end?.y || 0, t);
  const length = Math.hypot(x, y);

  if (length <= 0.0001) {
    return start || end || { x: 1, y: 0 };
  }

  return {
    x: x / length,
    y: y / length
  };
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

function normalizedVector(from, to) {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const length = Math.hypot(dx, dy);

  if (length <= 0.0001) {
    return { x: 1, y: 0 };
  }

  return {
    x: dx / length,
    y: dy / length
  };
}

function distance(from, to) {
  return Math.hypot(to.x - from.x, to.y - from.y);
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

function clamp01(value) {
  return Math.min(1, Math.max(0, value));
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

cameraButton.addEventListener("click", startCamera);
undoButton.addEventListener("click", () => {
  strokes.pop();
  resetCommittedStrokes();
  redraw();
});
clearButton.addEventListener("click", () => {
  strokes = [];
  activeSamples = [];
  clearWorkCanvas(committedContext);
  resetCommittedStrokes();
  redraw();
});
widthControl.addEventListener("input", () => {
  if (!isDrawing) {
    return;
  }
  const previous = activeSamples.at(-1);
  if (previous) {
    appendSample(samplePoint(previous), performance.now(), true);
    scheduleRedraw();
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
