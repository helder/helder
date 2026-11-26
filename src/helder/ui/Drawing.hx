package helder.ui;

import helder.gfx.Color;

// what Svg.render keeps as the image's drawing (Image.drawing), for a
// writer to draw as vectors instead of the pixels: the drawing in its
// colour (currentColor's): var d:ImageDrawing = image.drawing. A
// gradient's image (Gradient.render, a box's background) keeps the
// gradient and its scale instead (svg null)
typedef ImageDrawing = {?svg:Svg, ?color:Color, ?gradient:Gradient, ?scale:Float};
