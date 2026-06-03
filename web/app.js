const video = document.querySelector("#camera");
const canvas = document.querySelector("#paint");
const freezeCanvas = document.querySelector("#freezeFrame");
const stage = document.querySelector(".stage");
const viewport = document.querySelector(".viewport");
const cameraButton = document.querySelector("#cameraButton");
const undoButton = document.querySelector("#undoButton");
const clearButton = document.querySelector("#clearButton");
const saveButton = document.querySelector("#saveButton");
const widthControl = document.querySelector("#widthControl");
const sampleWidthControl = document.querySelector("#sampleWidthControl");
const statusOutput = document.querySelector("#status");

const context = canvas.getContext("2d", { alpha: true, desynchronized: true });
const freezeContext = freezeCanvas.getContext("2d", { alpha: false });
const committedCanvas = document.createElement("canvas");
const committedContext = committedCanvas.getContext("2d", { alpha: true, desynchronized: true });
const textureCanvas = document.createElement("canvas");
const textureContext = textureCanvas.getContext("2d", { alpha: true });
const maskCanvas = document.createElement("canvas");
const maskContext = maskCanvas.getContext("2d", { alpha: true });
const strokeTextureCanvas = document.createElement("canvas");
const strokeTextureContext = strokeTextureCanvas.getContext("2d", { alpha: true });

const sectionResolution = 256;
const sectionSampleWidth = 4;
const maximumRibbonSegmentLength = 6;
const tangentSmoothing = 0.58;
const textureColumnBleed = 0.18;
const ribbonOverdraw = 0.75;
const triangleClipBleed = 0.9;
const maximumStrokeTextureScale = 2.5;
const minimumStrokeTextureScale = 1;
const maximumStrokeTextureWidth = 8192;
const portraitSaveWidth = 1200;
const portraitSaveHeight = 1800;
const landscapeSaveWidth = 1800;
const landscapeSaveHeight = 1200;
const saveMimeType = "image/jpeg";
const saveFileExtension = "jpg";
const saveImageQuality = 0.92;
const shareSheetDelayMs = 1000;
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
  const { width, height } = viewSize();
  canvas.width = Math.max(1, Math.round(width * dpr));
  canvas.height = Math.max(1, Math.round(height * dpr));
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  resizeWorkCanvas(freezeCanvas, freezeContext, width, height);
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
  targetCanvas.style.width = `${width}px`;
  targetCanvas.style.height = `${height}px`;
  targetContext.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function viewSize() {
  const rect = viewport.getBoundingClientRect();
  return {
    width: Math.max(1, rect.width || window.innerWidth),
    height: Math.max(1, rect.height || window.innerHeight)
  };
}

function isLandscapeView() {
  const { width, height } = viewSize();
  return width > height;
}

async function startCamera() {
  if (!navigator.mediaDevices?.getUserMedia) {
    statusOutput.value = "Camera API is unavailable in this browser.";
    updateCameraButtonVisibility();
    return;
  }

  cameraButton.disabled = true;
  updateCameraButtonVisibility();
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: { ideal: "environment" },
        width: { ideal: 1920 },
        height: { ideal: 1080 }
      }
    });
    video.srcObject = stream;
    for (const track of stream.getVideoTracks()) {
      track.addEventListener("ended", updateCameraButtonVisibility);
    }
    await video.play();
    statusOutput.value = "";
    updateCameraButtonVisibility();
  } catch (error) {
    statusOutput.value = error instanceof Error ? error.message : "Camera permission failed.";
    updateCameraButtonVisibility();
  } finally {
    cameraButton.disabled = false;
  }
}

function updateCameraButtonVisibility() {
  cameraButton.hidden = isCameraRunning();
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

function discardActiveStroke() {
  activeSamples = [];
  setDrawingState(false);
}

function stopToolPointerEvent(event) {
  event.stopPropagation();
}

function preventBrowserGesture(event) {
  event.preventDefault();
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
  const sampleWidth = Number(sampleWidthControl.value);
  const { width: viewWidth, height: viewHeight } = viewSize();
  const previous = activeSamples.at(-1);
  const angle = previous ? brushAngle(previous, point, currentBrushAngle) : currentBrushAngle;
  currentBrushAngle = angle;

  if (!force && previous && !shouldAppend(previous, point, brushWidth, sampleWidth, angle)) {
    return;
  }

  const section = captureSection(point, angle, sampleWidth);
  if (previous && canJoinTemporalSample(previous, point, brushWidth)) {
    joinTemporalSample(previous, point, brushWidth, sampleWidth, angle, timestamp, section);
    return;
  }

  activeSamples.push({
    nx: point.x / viewWidth,
    ny: point.y / viewHeight,
    width: brushWidth,
    sampleWidth,
    angle,
    timestamp,
    joinCount: 1,
    section
  });
}

function shouldAppend(previous, point, width, sampleWidth, angle) {
  const previousPoint = samplePoint(previous);
  const dx = point.x - previousPoint.x;
  const dy = point.y - previousPoint.y;
  const distance = Math.hypot(dx, dy);
  const widthDelta = Math.abs(width - previous.width);
  const sampleWidthDelta = Math.abs(sampleWidth - (previous.sampleWidth || sampleWidth));
  const angleDelta = angularDistance(angle, previous.angle);
  return distance >= minimumPointDistance
    || widthDelta >= 1
    || sampleWidthDelta >= 1
    || angleDelta >= minimumAngleDelta;
}

function canJoinTemporalSample(previous, point, width) {
  const previousPoint = samplePoint(previous);
  const radius = Math.min(
    temporalJoinRadius,
    Math.max(3, Math.min(previous.width, width) * 0.14)
  );
  return distance(previousPoint, point) <= radius;
}

function joinTemporalSample(previous, point, width, sampleWidth, angle, timestamp, section) {
  const joinCount = (previous.joinCount || 1) + 1;
  const weight = 1 / joinCount;
  const { width: viewWidth, height: viewHeight } = viewSize();

  previous.nx = interpolate(previous.nx, point.x / viewWidth, weight);
  previous.ny = interpolate(previous.ny, point.y / viewHeight, weight);
  previous.width = interpolate(previous.width, width, weight);
  previous.sampleWidth = interpolate(previous.sampleWidth || sampleWidth, sampleWidth, weight);
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

function captureSection(point, angle, sampleWidth) {
  const mapping = screenToVideo(point);
  if (!mapping) {
    return null;
  }

  const cross = crossVector(angle);
  const tangent = { x: cross.y, y: -cross.x };
  const lineLength = Math.max(2, sampleWidth * mapping.scale);
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
  const { width, height } = viewSize();
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

async function saveComposition() {
  if (!isCameraReady()) {
    statusOutput.value = "Camera is not ready.";
    return;
  }

  redraw();
  saveButton.disabled = true;
  try {
    const exportCanvas = renderSaveCanvas();
    showFrozenComposition(exportCanvas);
    pauseCameraPreview();
    const blob = await canvasToBlob(exportCanvas, saveMimeType, saveImageQuality);
    const filename = `scene-ink-${timestampForFileName()}.${saveFileExtension}`;
    await wait(shareSheetDelayMs);
    await deliverSavedImage(blob, filename);
  } catch (error) {
    if (error?.name !== "AbortError") {
      statusOutput.value = error instanceof Error ? error.message : "Save failed.";
    }
  } finally {
    hideFrozenComposition();
    await resumeCameraPreview();
    saveButton.disabled = false;
  }
}

function renderSaveCanvas() {
  const { width, height } = saveOutputSize();
  const exportCanvas = document.createElement("canvas");
  exportCanvas.width = width;
  exportCanvas.height = height;
  const exportContext = exportCanvas.getContext("2d", { alpha: false });

  exportContext.imageSmoothingEnabled = true;
  exportContext.imageSmoothingQuality = "high";
  exportContext.fillStyle = "#050505";
  exportContext.fillRect(0, 0, width, height);
  drawVideoFrame(exportContext, width, height);
  drawPaintFrame(exportContext, width, height);
  return exportCanvas;
}

function saveOutputSize() {
  if (isLandscapeView()) {
    return {
      width: landscapeSaveWidth,
      height: landscapeSaveHeight
    };
  }

  return {
    width: portraitSaveWidth,
    height: portraitSaveHeight
  };
}

function drawVideoFrame(targetContext, targetWidth, targetHeight) {
  const mapping = videoObjectFitCoverMapping();
  if (!mapping) {
    return;
  }

  targetContext.drawImage(
    video,
    mapping.offsetX,
    mapping.offsetY,
    mapping.viewWidth / mapping.scale,
    mapping.viewHeight / mapping.scale,
    0,
    0,
    targetWidth,
    targetHeight
  );
}

function drawPaintFrame(targetContext, targetWidth, targetHeight) {
  targetContext.drawImage(
    canvas,
    0,
    0,
    canvas.width,
    canvas.height,
    0,
    0,
    targetWidth,
    targetHeight
  );
}

function showFrozenComposition(exportCanvas) {
  const { width, height } = viewSize();
  freezeCanvas.hidden = false;
  freezeContext.setTransform(dpr, 0, 0, dpr, 0, 0);
  freezeContext.clearRect(0, 0, width, height);
  freezeContext.imageSmoothingEnabled = true;
  freezeContext.imageSmoothingQuality = "high";
  freezeContext.drawImage(exportCanvas, 0, 0, width, height);
}

function hideFrozenComposition() {
  freezeCanvas.hidden = true;
}

function pauseCameraPreview() {
  video.pause();
}

async function resumeCameraPreview() {
  if (!video.srcObject) {
    updateCameraButtonVisibility();
    return;
  }

  try {
    await video.play();
    statusOutput.value = "";
  } catch (error) {
    statusOutput.value = error instanceof Error ? error.message : "Camera resume failed.";
  } finally {
    updateCameraButtonVisibility();
  }
}

function wait(ms) {
  return new Promise(resolve => {
    window.setTimeout(resolve, ms);
  });
}

function canvasToBlob(sourceCanvas, type, quality) {
  return new Promise((resolve, reject) => {
    sourceCanvas.toBlob(blob => {
      if (blob) {
        resolve(blob);
        return;
      }
      reject(new Error("Could not encode image."));
    }, type, quality);
  });
}

async function deliverSavedImage(blob, filename) {
  const file = new File([blob], filename, {
    type: blob.type || saveMimeType,
    lastModified: Date.now()
  });
  if (navigator.canShare?.({ files: [file] })) {
    await navigator.share({
      files: [file],
      title: filename,
      text: filename
    });
    statusOutput.value = "";
    return;
  }

  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  statusOutput.value = "";
}

function timestampForFileName() {
  return new Date().toISOString().replace(/[:.]/g, "-");
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

  const ribbon = buildRibbon(samples);
  if (ribbon.renderSamples.length < 2) {
    return;
  }

  const strokeTexture = buildStrokeTexture(ribbon.nodes, ribbon.length, ribbon.textureScale);
  drawTexturedStroke(ribbon.renderSamples, strokeTexture, ribbon.textureScale);
  maskTexturedStroke(ribbon.renderSamples);
  destinationContext.save();
  destinationContext.setTransform(1, 0, 0, 1, 0, 0);
  destinationContext.drawImage(textureCanvas, 0, 0);
  destinationContext.restore();
}

function drawTexturedStroke(renderSamples, strokeTexture, textureScale) {
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
      previous.u * textureScale,
      current.u * textureScale,
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
    const current = points[index];
    const next = points[index + 1];
    targetContext.quadraticCurveTo(
      current.x,
      current.y,
      (current.x + next.x) / 2,
      (current.y + next.y) / 2
    );
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

function buildStrokeTexture(nodes, length, textureScale) {
  strokeTextureCanvas.width = Math.max(2, Math.ceil(length * textureScale) + 1);
  strokeTextureCanvas.height = sectionResolution;
  strokeTextureContext.setTransform(1, 0, 0, 1, 0, 0);
  strokeTextureContext.clearRect(0, 0, strokeTextureCanvas.width, strokeTextureCanvas.height);
  strokeTextureContext.imageSmoothingEnabled = true;
  strokeTextureContext.imageSmoothingQuality = "high";

  if (nodes.length < 2 || length <= 0) {
    return strokeTextureCanvas;
  }

  let segmentIndex = 1;
  for (let column = 0; column < strokeTextureCanvas.width; column += 1) {
    const position = Math.min(length, column / textureScale);
    while (segmentIndex < nodes.length - 1 && nodes[segmentIndex].u < position) {
      segmentIndex += 1;
    }

    const previous = nodes[Math.max(0, segmentIndex - 1)];
    const current = nodes[segmentIndex];
    const next = nodes[Math.min(nodes.length - 1, segmentIndex + 1)];
    const segmentLength = Math.max(0.001, current.u - previous.u);
    const t = clamp01((position - previous.u) / segmentLength);
    drawBlendedTextureColumn(strokeTextureContext, previous, current, t, column, 1);
    drawBlendedTextureColumn(strokeTextureContext, previous, current, t, column - 1, textureColumnBleed);
    drawBlendedTextureColumn(strokeTextureContext, previous, current, t, column + 1, textureColumnBleed);

    if (t > 0.82 && next !== current) {
      const nextT = (t - 0.82) / 0.18;
      drawBlendedTextureColumn(strokeTextureContext, current, next, nextT, column, textureColumnBleed * nextT);
    }
  }

  strokeTextureContext.globalAlpha = 1;
  return strokeTextureCanvas;
}

function drawBlendedTextureColumn(targetContext, start, end, t, column, alpha) {
  if (column < 0 || column >= targetContext.canvas.width || alpha <= 0) {
    return;
  }

  if (start?.section) {
    drawTextureColumn(targetContext, start.section, column, alpha);
  }

  if (end?.section && end !== start && t > 0) {
    drawTextureColumn(targetContext, end.section, column, alpha * clamp01(t));
  }
}

function drawTextureColumn(targetContext, section, column, alpha) {
  if (!section || alpha <= 0) {
    return;
  }

  targetContext.globalAlpha = alpha;
  targetContext.drawImage(
    section,
    0,
    0,
    section.width,
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

function buildRibbon(samples) {
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
  assignRibbonDistances(nodes);

  const length = nodes.at(-1)?.u || 0;
  const textureScale = strokeTextureScaleForLength(length);
  return {
    nodes,
    length,
    textureScale,
    renderSamples: splitLongRibbonSegments(nodes)
  };
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

function assignRibbonDistances(nodes) {
  let length = 0;
  if (nodes[0]) {
    nodes[0].u = 0;
  }

  for (let index = 1; index < nodes.length; index += 1) {
    length += distance(nodes[index - 1], nodes[index]);
    nodes[index].u = length;
  }
}

function strokeTextureScaleForLength(length) {
  const preferredScale = Math.min(maximumStrokeTextureScale, Math.max(1.5, dpr));
  if (length <= 0) {
    return preferredScale;
  }

  const fittingScale = (maximumStrokeTextureWidth - 1) / length;
  return Math.max(minimumStrokeTextureScale, Math.min(preferredScale, fittingScale));
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
    u: interpolate(start.u, end.u, t)
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
  const mapping = videoObjectFitCoverMapping();
  if (!mapping) {
    return null;
  }

  return {
    x: mapping.offsetX + point.x / mapping.scale,
    y: mapping.offsetY + point.y / mapping.scale,
    scale: 1 / mapping.scale
  };
}

function videoObjectFitCoverMapping() {
  const videoWidth = video.videoWidth;
  const videoHeight = video.videoHeight;
  const { width: viewWidth, height: viewHeight } = viewSize();

  if (!videoWidth || !videoHeight || !viewWidth || !viewHeight) {
    return null;
  }

  const scale = Math.max(viewWidth / videoWidth, viewHeight / videoHeight);
  const visibleWidth = viewWidth / scale;
  const visibleHeight = viewHeight / scale;
  const offsetX = (videoWidth - visibleWidth) / 2;
  const offsetY = (videoHeight - visibleHeight) / 2;

  return {
    offsetX,
    offsetY,
    viewWidth,
    viewHeight,
    scale
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
  const { width, height } = viewSize();
  return {
    x: sample.nx * width,
    y: sample.ny * height
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

function isCameraRunning() {
  const stream = video.srcObject;
  if (!(stream instanceof MediaStream)) {
    return false;
  }

  return stream.getVideoTracks().some(track => track.readyState === "live");
}

for (const control of [cameraButton, saveButton, undoButton, clearButton, widthControl, sampleWidthControl]) {
  control.addEventListener("pointerdown", stopToolPointerEvent);
  control.addEventListener("pointermove", stopToolPointerEvent);
  control.addEventListener("pointerup", stopToolPointerEvent);
}

cameraButton.addEventListener("click", event => {
  event.stopPropagation();
  startCamera();
});
saveButton.addEventListener("click", event => {
  event.stopPropagation();
  setDrawingState(false);
  saveComposition();
});
undoButton.addEventListener("click", event => {
  event.stopPropagation();
  discardActiveStroke();
  strokes.pop();
  resetCommittedStrokes();
  redraw();
});
clearButton.addEventListener("pointerdown", () => {
  discardActiveStroke();
});
clearButton.addEventListener("click", event => {
  event.stopPropagation();
  discardActiveStroke();
  strokes = [];
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
sampleWidthControl.addEventListener("input", () => {
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

video.addEventListener("loadeddata", updateCameraButtonVisibility);
video.addEventListener("playing", updateCameraButtonVisibility);
video.addEventListener("emptied", updateCameraButtonVisibility);
document.addEventListener("contextmenu", preventBrowserGesture);
document.addEventListener("dragstart", preventBrowserGesture);
document.addEventListener("selectstart", preventBrowserGesture);
document.addEventListener("gesturestart", preventBrowserGesture);
document.addEventListener("gesturechange", preventBrowserGesture);
document.addEventListener("gestureend", preventBrowserGesture);
window.addEventListener("resize", resizeCanvas);
resizeCanvas();
redraw();
startCamera();
