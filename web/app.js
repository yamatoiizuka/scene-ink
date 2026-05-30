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
const segmentTextureCanvas = document.createElement("canvas");
const segmentTextureContext = segmentTextureCanvas.getContext("2d", { alpha: true });

const sectionResolution = 128;
const sectionSampleWidth = 2;
const segmentTextureColumns = 6;
const skeletonSampleSpacing = 1.7;
const bezierTension = 0.82;
const ribbonOverdraw = 0.75;
const minimumPointDistance = 4.5;
const minimumAngleDelta = Math.PI / 90;
const temporalJoinRadius = 5;
const temporalJoinColumnStep = 3;
const temporalJoinMaxColumns = 20;

segmentTextureCanvas.width = segmentTextureColumns;
segmentTextureCanvas.height = sectionResolution;

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

  const skeleton = buildBezierSkeleton(samples);
  const renderSamples = sampleBezierSkeleton(skeleton);
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

  for (let index = 1; index < renderSamples.length; index += 1) {
    const previous = renderSamples[index - 1];
    const current = renderSamples[index];
    if (distance(previous, current) <= 0.001) {
      continue;
    }

    const texture = buildSegmentTexture(previous, current);
    drawRibbonSegment(
      textureContext,
      texture,
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

function buildSegmentTexture(previous, current) {
  segmentTextureContext.setTransform(1, 0, 0, 1, 0, 0);
  segmentTextureContext.clearRect(0, 0, segmentTextureCanvas.width, segmentTextureCanvas.height);
  segmentTextureContext.imageSmoothingEnabled = true;
  segmentTextureContext.imageSmoothingQuality = "high";

  for (let column = 0; column < segmentTextureCanvas.width; column += 1) {
    const t = segmentTextureCanvas.width === 1 ? 0 : column / (segmentTextureCanvas.width - 1);
    drawResolvedSectionColumn(segmentTextureContext, previous, column, 1);
    drawResolvedSectionColumn(segmentTextureContext, current, column, t);
  }

  segmentTextureContext.globalAlpha = 1;
  return segmentTextureCanvas;
}

function drawResolvedSectionColumn(targetContext, sample, column, alpha) {
  if (alpha <= 0) {
    return;
  }

  targetContext.save();
  if (sample.previousSection) {
    targetContext.globalAlpha = alpha;
    drawSectionColumn(targetContext, sample.previousSection, column);
  }
  if (sample.currentSection) {
    targetContext.globalAlpha = alpha * Math.min(1, sample.sectionT);
    drawSectionColumn(targetContext, sample.currentSection, column);
  }
  targetContext.restore();
}

function drawSectionColumn(targetContext, section, column) {
  targetContext.drawImage(
    section,
    0,
    0,
    section.width,
    section.height,
    column,
    0,
    1,
    segmentTextureCanvas.height
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

function drawRibbonSegment(targetContext, texture, previousFrame, currentFrame) {
  const sourceTopLeft = { x: 0, y: 0 };
  const sourceTopRight = { x: texture.width, y: 0 };
  const sourceBottomLeft = { x: 0, y: texture.height };
  const sourceBottomRight = { x: texture.width, y: texture.height };

  drawTexturedTriangle(
    targetContext,
    texture,
    [sourceTopLeft, sourceTopRight, sourceBottomLeft],
    [previousFrame.top, currentFrame.top, previousFrame.bottom]
  );
  drawTexturedTriangle(
    targetContext,
    texture,
    [sourceBottomLeft, sourceTopRight, sourceBottomRight],
    [previousFrame.bottom, currentFrame.top, currentFrame.bottom]
  );
}

function drawTexturedTriangle(targetContext, texture, sourceTriangle, destinationTriangle) {
  const matrix = triangleTransform(sourceTriangle, destinationTriangle);
  if (!matrix) {
    return;
  }

  targetContext.save();
  targetContext.beginPath();
  targetContext.moveTo(destinationTriangle[0].x, destinationTriangle[0].y);
  targetContext.lineTo(destinationTriangle[1].x, destinationTriangle[1].y);
  targetContext.lineTo(destinationTriangle[2].x, destinationTriangle[2].y);
  targetContext.closePath();
  targetContext.clip();
  targetContext.transform(matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f);
  targetContext.drawImage(texture, 0, 0);
  targetContext.restore();
}

function triangleTransform(sourceTriangle, destinationTriangle) {
  const [source0, source1, source2] = sourceTriangle;
  const [destination0, destination1, destination2] = destinationTriangle;
  const denominator = source0.x * (source1.y - source2.y)
    + source1.x * (source2.y - source0.y)
    + source2.x * (source0.y - source1.y);

  if (Math.abs(denominator) <= 0.0001) {
    return null;
  }

  return {
    a: (destination0.x * (source1.y - source2.y)
      + destination1.x * (source2.y - source0.y)
      + destination2.x * (source0.y - source1.y)) / denominator,
    b: (destination0.y * (source1.y - source2.y)
      + destination1.y * (source2.y - source0.y)
      + destination2.y * (source0.y - source1.y)) / denominator,
    c: (destination0.x * (source2.x - source1.x)
      + destination1.x * (source0.x - source2.x)
      + destination2.x * (source1.x - source0.x)) / denominator,
    d: (destination0.y * (source2.x - source1.x)
      + destination1.y * (source0.x - source2.x)
      + destination2.y * (source1.x - source0.x)) / denominator,
    e: (destination0.x * (source1.x * source2.y - source2.x * source1.y)
      + destination1.x * (source2.x * source0.y - source0.x * source2.y)
      + destination2.x * (source0.x * source1.y - source1.x * source0.y)) / denominator,
    f: (destination0.y * (source1.x * source2.y - source2.x * source1.y)
      + destination1.y * (source2.x * source0.y - source0.x * source2.y)
      + destination2.y * (source0.x * source1.y - source1.x * source0.y)) / denominator
  };
}

function buildBezierSkeleton(samples) {
  const nodes = samples.map(sample => ({
    x: samplePoint(sample).x,
    y: samplePoint(sample).y,
    width: sample.width,
    section: sample.section
  }));
  const segments = [];

  for (let index = 0; index < nodes.length - 1; index += 1) {
    const previous = nodes[Math.max(0, index - 1)];
    const current = nodes[index];
    const next = nodes[index + 1];
    const afterNext = nodes[Math.min(nodes.length - 1, index + 2)];
    const control1 = {
      x: current.x + (next.x - previous.x) * bezierTension / 6,
      y: current.y + (next.y - previous.y) * bezierTension / 6
    };
    const control2 = {
      x: next.x - (afterNext.x - current.x) * bezierTension / 6,
      y: next.y - (afterNext.y - current.y) * bezierTension / 6
    };

    segments.push({
      start: current,
      control1,
      control2,
      end: next,
      length: estimateCubicLength(current, control1, control2, next)
    });
  }

  return segments;
}

function sampleBezierSkeleton(segments) {
  const renderSamples = [];
  let previousTangent = { x: 1, y: 0 };

  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index];
    const steps = Math.max(2, Math.ceil(segment.length / skeletonSampleSpacing));
    const startStep = index === 0 ? 0 : 1;

    for (let step = startStep; step <= steps; step += 1) {
      const t = step / steps;
      const point = cubicBezierPoint(segment.start, segment.control1, segment.control2, segment.end, t);
      const tangent = cubicBezierTangent(
        segment.start,
        segment.control1,
        segment.control2,
        segment.end,
        t,
        previousTangent
      );
      previousTangent = tangent;
      renderSamples.push({
        x: point.x,
        y: point.y,
        tangent,
        width: interpolate(segment.start.width, segment.end.width, t),
        previousSection: segment.start.section,
        currentSection: segment.end.section,
        sectionT: t
      });
    }
  }

  return renderSamples;
}

function estimateCubicLength(start, control1, control2, end) {
  const steps = 12;
  let length = 0;
  let previous = start;

  for (let step = 1; step <= steps; step += 1) {
    const point = cubicBezierPoint(start, control1, control2, end, step / steps);
    length += distance(previous, point);
    previous = point;
  }

  return length;
}

function cubicBezierPoint(start, control1, control2, end, t) {
  const inverse = 1 - t;
  const inverse2 = inverse * inverse;
  const t2 = t * t;

  return {
    x: inverse2 * inverse * start.x
      + 3 * inverse2 * t * control1.x
      + 3 * inverse * t2 * control2.x
      + t2 * t * end.x,
    y: inverse2 * inverse * start.y
      + 3 * inverse2 * t * control1.y
      + 3 * inverse * t2 * control2.y
      + t2 * t * end.y
  };
}

function cubicBezierTangent(start, control1, control2, end, t, fallback) {
  const inverse = 1 - t;
  const x = 3 * inverse * inverse * (control1.x - start.x)
    + 6 * inverse * t * (control2.x - control1.x)
    + 3 * t * t * (end.x - control2.x);
  const y = 3 * inverse * inverse * (control1.y - start.y)
    + 6 * inverse * t * (control2.y - control1.y)
    + 3 * t * t * (end.y - control2.y);
  const length = Math.hypot(x, y);

  if (length <= 0.0001) {
    return fallback;
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
