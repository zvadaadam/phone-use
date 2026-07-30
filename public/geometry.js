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
