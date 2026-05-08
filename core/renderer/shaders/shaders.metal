#include <metal_stdlib>

using namespace metal;

struct Uniforms {
  float4x4 projection_matrix;
  float2 screen_size;
  float2 cell_size;
  ushort2 grid_size;
  ushort2 cursor_pos;
  uchar4 cursor_color;
  uchar4 bg_color;
};

struct FullScreenVertexOut {
  float4 position [[position]];
};

vertex FullScreenVertexOut full_screen_vertex(
  uint vid [[vertex_id]]
) {
  FullScreenVertexOut out;

  float4 position;
  position.x = (vid == 2) ? 3.0 : -1.0;
  position.y = (vid == 0) ? -3.0 : 1.0;
  position.zw = 1.0;

  // Single triangle is clipped to viewport.
  //
  // X <- vid == 0: (-1, -3)
  // |\
  // | \
  // |  \
  // |###\
  // |#+# \ `+` is (0, 0). `#`s are viewport area.
  // |###  \
  // X------X <- vid == 2: (3, 1)
  // ^
  // vid == 1: (-1, 1)

  out.position = position;

  return out;
}

fragment float4 bg_color_fragment(
  FullScreenVertexOut in [[stage_in]],
  constant Uniforms& uniforms [[buffer(1)]]
) {
  float4 color = float4(uniforms.bg_color) / 255.0f;

  return color;
}

struct VertexInput {
    float4 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct VertexOutput {
    float4 position [[position]];
    float4 color [[flat]];
};

vertex VertexOutput vertexShader(VertexInput in [[stage_in]]) {
    VertexOutput out;
    out.position = in.position;
    out.color = in.color;
    return out;
}

fragment float4 fragmentShader(VertexOutput in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    float2 fragCoord = in.position.xy;

    float line_thickness = 2.0f;

    bool is_horizontal_line = (fmod(fragCoord.y, uniforms.cell_size.y) < line_thickness) ||
                              (fmod(fragCoord.y, uniforms.cell_size.y) > (uniforms.cell_size.y - line_thickness));

    bool is_vertical_line = (fmod(fragCoord.x, uniforms.cell_size.x) < line_thickness) ||
                            (fmod(fragCoord.x, uniforms.cell_size.x) > (uniforms.cell_size.x - line_thickness));

    if (is_horizontal_line || is_vertical_line) {
        return float4(0.5f, 0.5f, 0.5f, 1.0f);
    }

    return in.color;
}

// We use a packed struct of bools for misc properties of the glyph.
enum CellTextBools : uint8_t {
  // Don't apply min contrast to this glyph.
  NO_MIN_CONTRAST = 1u,
  // This is the cursor glyph.
  IS_CURSOR_GLYPH = 2u,
};

struct CellTextVertexIn {
  // The position of the glyph in the texture (x, y)
  uint2 glyph_pos [[attribute(0)]];

  // The size of the glyph in the texture (w, h)
  uint2 glyph_size [[attribute(1)]];

  // The left and top bearings for the glyph (x, y)
  int2 bearings [[attribute(2)]];

  // The grid coordinates (x, y) where x < columns and y < rows
  ushort2 grid_pos [[attribute(3)]];

  // The color of the rendered text glyph.
  uchar4 color [[attribute(4)]];

  // Misc properties of the glyph.
  uint8_t bools [[attribute(5)]];
};

struct CellTextVertexOut {
  float4 position [[position]];
  float4 color [[flat]];
  float2 tex_coord;
};

vertex CellTextVertexOut cell_text_vertex(
  uint vid [[vertex_id]],
  CellTextVertexIn in [[stage_in]],
  constant Uniforms& uniforms [[buffer(1)]]
) {
  // Convert the grid x, y into world space x, y by accounting for cell size
  float2 cell_pos = uniforms.cell_size * float2(in.grid_pos);

  // We use a triangle strip with 4 vertices to render quads,
  // so we determine which corner of the cell this vertex is in
  // based on the vertex ID.
  //
  //   0 --> 1
  //   |   .'|
  //   |  /  |
  //   | L   |
  //   2 --> 3
  //
  // 0 = top-left  (0, 0)
  // 1 = top-right (1, 0)
  // 2 = bot-left  (0, 1)
  // 3 = bot-right (1, 1)
  float2 corner;
  corner.x = float(vid == 1 || vid == 3);
  corner.y = float(vid == 2 || vid == 3);

  CellTextVertexOut out;
  //              === Grid Cell ===
  //      +X
  // 0,0--...->
  //   |
  //   . offset.x = bearings.x
  // +Y.               .|.
  //   .               | |
  //   |   cell_pos -> +-------+   _.
  //   v             ._|       |_. _|- offset.y = cell_size.y - bearings.y
  //                 | | .###. | |
  //                 | | #...# | |
  //   glyph_size.y -+ | ##### | |
  //                 | | #.... | +- bearings.y
  //                 |_| .#### | |
  //                   |       |_|
  //                   +-------+
  //                     |_._|
  //                       |
  //                  glyph_size.x
  //
  // In order to get the top left of the glyph, we compute an offset based on
  // the bearings. The Y bearing is the distance from the bottom of the cell
  // to the top of the glyph, so we subtract it from the cell height to get
  // the y offset. The X bearing is the distance from the left of the cell
  // to the left of the glyph, so it works as the x offset directly.

  float2 size = float2(in.glyph_size);
  float2 offset = float2(in.bearings);

  offset.y = uniforms.cell_size.y - offset.y;

  // Calculate the final position of the cell which uses our glyph size
  // and glyph offset to create the correct bounding box for the glyph.
  cell_pos = cell_pos + size * corner + offset;
  out.position =
      uniforms.projection_matrix * float4(cell_pos.x, cell_pos.y, 0.0f, 1.0f);

  // Calculate the texture coordinate in pixels. This is NOT normalized
  // (between 0.0 and 1.0), and does not need to be, since the texture will
  // be sampled with pixel coordinate mode.
  out.tex_coord = float2(in.glyph_pos) + float2(in.glyph_size) * corner;

  // Get our color. We always fetch a linearized version to
  // make it easier to handle minimum contrast calculations.
  out.color = float4(in.color) / 255.0f;

  // Check if current position is under cursor (including wide cursor)
  bool is_cursor_pos = (
      in.grid_pos.x == uniforms.cursor_pos.x
    ) && in.grid_pos.y == uniforms.cursor_pos.y;

  // If this cell is the cursor cell, but we're not processing
  // the cursor glyph itself, then we need to change the color.
  if ((in.bools & IS_CURSOR_GLYPH) == 0 && is_cursor_pos) {
    out.color = float4(1.0f, 0.0f, 0.0f, 1.0f);
  }


  return out;
}

fragment float4 cell_text_fragment(
  CellTextVertexOut in [[stage_in]],
  texture2d<float> textureGrayscale [[texture(0)]],
  constant Uniforms& uniforms [[buffer(1)]]
) {
  constexpr sampler textureSampler(
    coord::pixel,
    address::clamp_to_edge,
    filter::nearest
  );

      // Our input color is always linear.
      float4 color = in.color;

      // Fetch our alpha mask for this pixel.
      float a = textureGrayscale.sample(textureSampler, in.tex_coord).r;

      // Multiply our whole color by the alpha mask.
      // Since we use premultiplied alpha, this is
      // the correct way to apply the mask.
      color *= a;

      return color;
}

fragment float4 cell_bg_fragment(
  FullScreenVertexOut in [[stage_in]],
  constant Uniforms& uniforms [[buffer(1)]],
  constant uchar4 *cells [[buffer(2)]]
) {
  int2 grid_pos = int2(floor((in.position.xy) / uniforms.cell_size));

  float4 bg = float4(0.0);

  // Clamp x position, extends edge bg colors in to padding on sides.
 if (grid_pos.x < 0) {
     return bg;
 } else if (grid_pos.x > uniforms.grid_size.x - 1) {
     return bg;
 }

 // Clamp y position if we should extend, otherwise discard if out of bounds.
 if (grid_pos.y < 0) {
     return bg;
 } else if (grid_pos.y > uniforms.grid_size.y - 1) {
     return bg;
 }

  // Load the color for the cell.
  uchar4 cell_color = cells[grid_pos.y * uniforms.grid_size.x + grid_pos.x];

  float4 color = float4(cell_color) / 255.0f;

  return color;
}
