import 'dart:math';

import 'package:image/image.dart';

const _atlasSize = 256;
const _tileSize = 16;

void main() {
  final atlas = Image(width: _atlasSize, height: _atlasSize, numChannels: 4);
  atlas.clear(ColorRgba8(0, 0, 0, 0));
  final random = Random(0x4d696e65);

  _stone(atlas, 0, 0xFF7D7D7D, random);
  _stone(atlas, 1, 0xFF80512E, random);
  _grassTop(atlas, 2, random);
  _grassSide(atlas, 3, random);
  _stone(atlas, 4, 0xFFE2C879, random);
  _stone(atlas, 5, 0xFF77746D, random);
  _logSide(atlas, 6, random);
  _logTop(atlas, 7, random);
  _leaves(atlas, 8, random);
  _water(atlas, 9, random);
  _stone(atlas, 10, 0xFF373737, random, border: 0xFF181818);
  _ore(atlas, 11, 0xFF787878, 0xFF242424, random);
  _ore(atlas, 12, 0xFF787878, 0xFFD3B08A, random);
  _ore(atlas, 13, 0xFF787878, 0xFFF0C83B, random);
  _planks(atlas, 14, random);
  _stone(atlas, 15, 0xFF666666, random, border: 0xFF4F4F4F);
  _glass(atlas, 16);
  _bricks(atlas, 17);
  _sponge(atlas, 18, random);
  _flower(atlas, 19, 0xFFFFE542, 0xFF2C9638);
  _flower(atlas, 20, 0xFFE8494F, 0xFF2C9638);
  _mushroom(atlas, 21, 0xFFA4774A);
  _mushroom(atlas, 22, 0xFFD83B3B);
  _lava(atlas, 23, random);
  _tnt(atlas, 24, 25, 26, random);
  _sapling(atlas, 27);
  _metalBlock(atlas, 28, 0xFFF0C83B, random);
  _metalBlock(atlas, 29, 0xFFD8D8D8, random);
  _cloth(atlas, 30, 0xFFE5E5E5, random);
  _cloth(atlas, 31, 0xFFC83B3B, random);
  _cloth(atlas, 32, 0xFFDB762E, random);
  _cloth(atlas, 33, 0xFFE5CF42, random);
  _cloth(atlas, 34, 0xFF74B83D, random);
  _cloth(atlas, 35, 0xFF395FAF, random);

  encodePngFile('assets/textures/atlas.png', atlas, level: 9);
}

void _tile(Image atlas, int index, void Function(int x, int y) paint) {
  final originX = (index & 15) * _tileSize;
  final originY = (index >> 4) * _tileSize;
  for (var y = 0; y < _tileSize; y++) {
    for (var x = 0; x < _tileSize; x++) {
      paint(originX + x, originY + y);
    }
  }
}

void _stone(Image atlas, int index, int base, Random random, {int? border}) {
  _tile(atlas, index, (x, y) {
    final noise = random.nextInt(25) - 12;
    atlas.setPixelRgba(
      x,
      y,
      _channel(base, 16, noise),
      _channel(base, 8, noise),
      _channel(base, 0, noise),
      255,
    );
  });
  if (border != null) _frame(atlas, index, border);
}

void _grassTop(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    final noise = random.nextInt(31) - 15;
    atlas.setPixelRgba(
      x,
      y,
      84 + noise ~/ 3,
      154 + noise,
      57 + noise ~/ 4,
      255,
    );
  });
}

void _grassSide(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    final grass = y < 5 + random.nextInt(3);
    final base = grass ? 0xFF5B9D42 : 0xFF80512E;
    final noise = random.nextInt(21) - 10;
    atlas.setPixelRgba(
      x,
      y,
      _channel(base, 16, noise),
      _channel(base, 8, noise),
      _channel(base, 0, noise),
      255,
    );
  });
}

void _logSide(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    final stripe = (x ~/ 3).isEven ? 12 : -9;
    final noise = random.nextInt(9) - 4;
    atlas.setPixelRgba(
      x,
      y,
      125 + stripe + noise,
      82 + stripe ~/ 2 + noise,
      42 + noise,
      255,
    );
  });
}

void _logTop(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    final dx = x - 7.5;
    final dy = y - 7.5;
    final ring = (sqrt(dx * dx + dy * dy) / 2.7).floor().isEven;
    final noise = random.nextInt(9) - 4;
    final value = ring ? 145 : 114;
    atlas.setPixelRgba(
      x,
      y,
      value + noise,
      value - 40 + noise,
      50 + noise,
      255,
    );
  });
}

void _leaves(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    if (random.nextInt(13) == 0) {
      atlas.setPixelRgba(x, y, 0, 0, 0, 0);
      return;
    }
    final noise = random.nextInt(31) - 15;
    atlas.setPixelRgba(
      x,
      y,
      40 + noise ~/ 3,
      101 + noise,
      39 + noise ~/ 3,
      255,
    );
  });
}

void _water(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    final wave = (y ~/ 3).isEven ? 14 : -5;
    final noise = random.nextInt(11) - 5;
    atlas.setPixelRgba(
      x,
      y,
      42 + noise,
      112 + wave + noise,
      201 + wave + noise,
      180,
    );
  });
}

void _ore(Image atlas, int index, int stone, int fleck, Random random) {
  _stone(atlas, index, stone, random);
  final ox = (index & 15) * _tileSize;
  final oy = (index >> 4) * _tileSize;
  for (var i = 0; i < 20; i++) {
    final x = ox + 1 + random.nextInt(14);
    final y = oy + 1 + random.nextInt(14);
    atlas.setPixelRgba(
      x,
      y,
      _channel(fleck, 16, 0),
      _channel(fleck, 8, 0),
      _channel(fleck, 0, 0),
      255,
    );
  }
}

void _planks(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    final seam = y % 5 == 0 || x == 0 || x == 15;
    final noise = random.nextInt(11) - 5;
    final base = seam ? 0xFF70451F : 0xFFA46B35;
    atlas.setPixelRgba(
      x,
      y,
      _channel(base, 16, noise),
      _channel(base, 8, noise),
      _channel(base, 0, noise),
      255,
    );
  });
}

void _glass(Image atlas, int index) {
  _tile(atlas, index, (x, y) {
    final edge =
        x == 0 || x == 15 || y == 0 || y == 15 || x == y || x + y == 15;
    atlas.setPixelRgba(x, y, 171, 232, 255, edge ? 170 : 42);
  });
}

void _bricks(Image atlas, int index) {
  _tile(atlas, index, (x, y) {
    final seam = y % 5 == 0 || (x + ((y ~/ 5).isEven ? 0 : 4)) % 8 == 0;
    atlas.setPixelRgba(
      x,
      y,
      seam ? 91 : 169,
      seam ? 45 : 69,
      seam ? 34 : 48,
      255,
    );
  });
}

void _sponge(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    final dark = random.nextInt(6) == 0;
    atlas.setPixelRgba(
      x,
      y,
      dark ? 180 : 230,
      dark ? 160 : 207,
      dark ? 35 : 57,
      255,
    );
  });
  _frame(atlas, index, 0xFFB3971D);
}

void _flower(Image atlas, int index, int petal, int stem) {
  _tile(atlas, index, (x, y) => atlas.setPixelRgba(x, y, 0, 0, 0, 0));
  final ox = (index & 15) * _tileSize;
  final oy = (index >> 4) * _tileSize;
  for (var y = 4; y < 9; y++) {
    for (var x = 5; x < 11; x++) {
      if ((x - 8).abs() + (y - 6).abs() <= 3) {
        atlas.setPixelRgba(
          x + ox,
          y + oy,
          _channel(petal, 16, 0),
          _channel(petal, 8, 0),
          _channel(petal, 0, 0),
          255,
        );
      }
    }
  }
  for (var y = 8; y < 15; y++) {
    atlas.setPixelRgba(
      ox + 8,
      oy + y,
      _channel(stem, 16, 0),
      _channel(stem, 8, 0),
      _channel(stem, 0, 0),
      255,
    );
  }
}

void _mushroom(Image atlas, int index, int cap) {
  _tile(atlas, index, (x, y) => atlas.setPixelRgba(x, y, 0, 0, 0, 0));
  final ox = (index & 15) * _tileSize;
  final oy = (index >> 4) * _tileSize;
  for (var y = 4; y < 10; y++) {
    for (var x = 3; x < 13; x++) {
      if ((x - 8).abs() + (y - 8).abs() <= 6) {
        atlas.setPixelRgba(
          x + ox,
          y + oy,
          _channel(cap, 16, 0),
          _channel(cap, 8, 0),
          _channel(cap, 0, 0),
          255,
        );
      }
    }
  }
  for (var y = 9; y < 15; y++) {
    atlas.setPixelRgba(ox + 7, oy + y, 217, 199, 159, 255);
    atlas.setPixelRgba(ox + 8, oy + y, 217, 199, 159, 255);
  }
}

void _lava(Image atlas, int index, Random random) {
  _tile(atlas, index, (x, y) {
    final stripe = ((x + y) ~/ 3).isEven ? 28 : -8;
    final noise = random.nextInt(17) - 8;
    atlas.setPixelRgba(
      x,
      y,
      (220 + stripe + noise).clamp(0, 255),
      (82 + stripe ~/ 2 + noise).clamp(0, 255),
      (18 + noise ~/ 2).clamp(0, 255),
      230,
    );
  });
}

void _tnt(Image atlas, int side, int top, int bottom, Random random) {
  _tile(atlas, side, (x, y) {
    final band = y >= 6 && y <= 9;
    final noise = random.nextInt(13) - 6;
    atlas.setPixelRgba(
      x,
      y,
      band ? 225 + noise : 176 + noise,
      band ? 214 + noise : 45 + noise,
      band ? 184 + noise : 35 + noise,
      255,
    );
  });
  // Blocky TNT lettering across the light band.
  final ox = (side & 15) * _tileSize;
  final oy = (side >> 4) * _tileSize;
  for (final x in <int>[3, 4, 7, 10, 11]) {
    atlas.setPixelRgba(ox + x, oy + 7, 45, 34, 29, 255);
    atlas.setPixelRgba(ox + x, oy + 8, 45, 34, 29, 255);
  }
  _tile(atlas, top, (x, y) {
    final dx = (x % 16) - 7.5;
    final dy = (y % 16) - 7.5;
    final ring = ((sqrt(dx * dx + dy * dy) / 2.2).floor()).isEven;
    atlas.setPixelRgba(x, y, ring ? 194 : 133, ring ? 62 : 38, 35, 255);
  });
  _stone(atlas, bottom, 0xFF8E5C3A, random);
}

void _sapling(Image atlas, int index) {
  _tile(atlas, index, (x, y) => atlas.setPixelRgba(x, y, 0, 0, 0, 0));
  final ox = (index & 15) * _tileSize;
  final oy = (index >> 4) * _tileSize;
  for (var y = 6; y < 15; y++) {
    atlas.setPixelRgba(ox + 8, oy + y, 93, 63, 31, 255);
  }
  for (var y = 3; y < 11; y++) {
    final radius = y < 6 ? 2 : 4;
    for (var x = 8 - radius; x <= 8 + radius; x++) {
      if (((x + y) & 1) == 0) {
        atlas.setPixelRgba(ox + x, oy + y, 48, 132, 51, 255);
      }
    }
  }
}

void _metalBlock(Image atlas, int index, int color, Random random) {
  _tile(atlas, index, (x, y) {
    final highlight = ((x % 16) + (y % 16)) < 13 ? 14 : -8;
    final noise = random.nextInt(7) - 3;
    atlas.setPixelRgba(
      x,
      y,
      _channel(color, 16, highlight + noise).clamp(0, 255),
      _channel(color, 8, highlight + noise).clamp(0, 255),
      _channel(color, 0, highlight + noise).clamp(0, 255),
      255,
    );
  });
}

void _cloth(Image atlas, int index, int color, Random random) {
  _tile(atlas, index, (x, y) {
    final weave = (((x + y) & 1) == 0) ? 7 : -5;
    final noise = random.nextInt(5) - 2;
    atlas.setPixelRgba(
      x,
      y,
      _channel(color, 16, weave + noise).clamp(0, 255),
      _channel(color, 8, weave + noise).clamp(0, 255),
      _channel(color, 0, weave + noise).clamp(0, 255),
      255,
    );
  });
}

void _frame(Image atlas, int index, int color) {
  final ox = (index & 15) * _tileSize;
  final oy = (index >> 4) * _tileSize;
  for (var i = 0; i < _tileSize; i++) {
    atlas.setPixelRgba(
      ox + i,
      oy,
      _channel(color, 16, 0),
      _channel(color, 8, 0),
      _channel(color, 0, 0),
      color >> 24,
    );
    atlas.setPixelRgba(
      ox + i,
      oy + 15,
      _channel(color, 16, 0),
      _channel(color, 8, 0),
      _channel(color, 0, 0),
      color >> 24,
    );
    atlas.setPixelRgba(
      ox,
      oy + i,
      _channel(color, 16, 0),
      _channel(color, 8, 0),
      _channel(color, 0, 0),
      color >> 24,
    );
    atlas.setPixelRgba(
      ox + 15,
      oy + i,
      _channel(color, 16, 0),
      _channel(color, 8, 0),
      _channel(color, 0, 0),
      color >> 24,
    );
  }
}

int _channel(int color, int shift, int delta) =>
    ((color >> shift) & 0xFF) + delta;
