export function containedFrame(rect, size) {
  if (!size?.width || !size?.height) return rect;

  const contentRatio = size.width / size.height;
  const boxRatio = rect.width / rect.height;
  if (contentRatio > boxRatio) {
    const height = rect.width / contentRatio;
    return {
      left: rect.left,
      top: rect.top + ((rect.height - height) / 2),
      width: rect.width,
      height,
    };
  }

  const width = rect.height * contentRatio;
  return {
    left: rect.left + ((rect.width - width) / 2),
    top: rect.top,
    width,
    height: rect.height,
  };
}

export function gestureCommand(start, end, durationMs) {
  const distance = Math.hypot(end.x - start.x, end.y - start.y);
  if (distance < 0.015) {
    return { type: "tap", x: end.x, y: end.y };
  }
  return {
    type: "swipe",
    x: start.x,
    y: start.y,
    x2: end.x,
    y2: end.y,
    durationMs: Math.round(Math.min(3_000, Math.max(100, durationMs))),
  };
}
