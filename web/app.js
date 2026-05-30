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

const sectionResolution = 128;
const sectionSampleWidth = 2;
const curveSampleSpacing = 2.25;
const stampOverlap = 3;
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

  const renderSamples = buildRenderSamples(samples);
  if (renderSamples.length < 2) {
    return;
  }

  drawTexturedStroke(renderSamples);
  maskTexturedStroke(renderSamples);
  destinationContext.save();
  destinationContext.setTransform(1, 0, 0, 1, 0, 0);
  destinationContext.drawImage(textureCanvas, 0, 0);
  destinationContext.restore();
}

function drawTexturedStroke(renderSamples) {
  clearWorkCanvas(textureContext);
  textureContext.imageSmoothingEnabled = true;
  textureContext.imageSmoothingQuality = "high";

  for (let index = 0; index < renderSamples.length; index += 1) {
    const current = renderSamples[index];
    const previous = renderSamples[Math.max(0, index - 1)];
    const next = renderSamples[Math.min(renderSamples.length - 1, index + 1)];
    const tangent = normalizedVector(previous, next);
    const cross = { x: -tangent.y, y: tangent.x };
    const thickness = Math.max(1, distance(previous, next) / 2 + stampOverlap);

    drawSlice(
      textureContext,
      current,
      tangent,
      cross,
      thickness
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

  if (endIndex - startIndex === 1) {
    const last = points[endIndex];
    targetContext.lineTo(last.x, last.y);
    return;
  }

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

function drawSlice(targetContext, sample, tangent, cross, thickness) {
  targetContext.save();
  targetContext.transform(
    tangent.x * thickness,
    tangent.y * thickness,
    cross.x * sample.width,
    cross.y * sample.width,
    sample.x,
    sample.y
  );

  if (sample.previousSection) {
    targetContext.globalAlpha = 1;
    targetContext.drawImage(sample.previousSection, -0.5, -0.5, 1, 1);
  }
  if (sample.currentSection) {
    targetContext.globalAlpha = Math.min(1, sample.sectionT);
    targetContext.drawImage(sample.currentSection, -0.5, -0.5, 1, 1);
  }

  targetContext.restore();
}

function buildRenderSamples(samples) {
  const renderSamples = [];

  for (let index = 0; index < samples.length - 1; index += 1) {
    const from = samplePoint(samples[index]);
    const to = samplePoint(samples[index + 1]);
    const segmentLength = Math.max(1, distance(from, to));
    const steps = Math.max(1, Math.ceil(segmentLength / curveSampleSpacing));
    const startStep = index === 0 ? 0 : 1;

    for (let step = startStep; step <= steps; step += 1) {
      const t = step / steps;
      const point = centripetalCatmullRomPoint(samples, index, t);
      renderSamples.push({
        x: point.x,
        y: point.y,
        width: interpolate(samples[index].width, samples[index + 1].width, t),
        previousSection: samples[index].section,
        currentSection: samples[index + 1].section,
        sectionT: t
      });
    }
  }

  return renderSamples;
}

function centripetalCatmullRomPoint(samples, index, amount) {
  const p0 = controlPoint(samples, index - 1);
  const p1 = controlPoint(samples, index);
  const p2 = controlPoint(samples, index + 1);
  const p3 = controlPoint(samples, index + 2);
  const t0 = 0;
  const t1 = knot(t0, p0, p1);
  const t2 = knot(t1, p1, p2);
  const t3 = knot(t2, p2, p3);
  const t = interpolate(t1, t2, amount);

  const a1 = interpolateKnot(p0, p1, t0, t1, t);
  const a2 = interpolateKnot(p1, p2, t1, t2, t);
  const a3 = interpolateKnot(p2, p3, t2, t3, t);
  const b1 = interpolateKnot(a1, a2, t0, t2, t);
  const b2 = interpolateKnot(a2, a3, t1, t3, t);
  return interpolateKnot(b1, b2, t1, t2, t);
}

function controlPoint(samples, index) {
  if (index >= 0 && index < samples.length) {
    return samplePoint(samples[index]);
  }

  if (index < 0) {
    const first = samplePoint(samples[0]);
    const second = samplePoint(samples[1] || samples[0]);
    return {
      x: first.x + (first.x - second.x),
      y: first.y + (first.y - second.y)
    };
  }

  const last = samplePoint(samples.at(-1));
  const previous = samplePoint(samples.at(-2) || samples.at(-1));
  return {
    x: last.x + (last.x - previous.x),
    y: last.y + (last.y - previous.y)
  };
}

function knot(previousKnot, previous, current) {
  return previousKnot + Math.sqrt(Math.max(0.0001, distance(previous, current)));
}

function interpolateKnot(start, end, startKnot, endKnot, amountKnot) {
  const span = endKnot - startKnot;
  if (span <= 0.0001) {
    return { ...start };
  }

  const amount = (amountKnot - startKnot) / span;
  return {
    x: interpolate(start.x, end.x, amount),
    y: interpolate(start.y, end.y, amount)
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
