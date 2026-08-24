/// Mutable axis-aligned bounding box used by the physics hot path.
library;

final class Aabb {
  Aabb({
    this.minX = 0,
    this.minY = 0,
    this.minZ = 0,
    this.maxX = 0,
    this.maxY = 0,
    this.maxZ = 0,
  });

  double minX;
  double minY;
  double minZ;
  double maxX;
  double maxY;
  double maxZ;

  void setValues(
    double newMinX,
    double newMinY,
    double newMinZ,
    double newMaxX,
    double newMaxY,
    double newMaxZ,
  ) {
    minX = newMinX;
    minY = newMinY;
    minZ = newMinZ;
    maxX = newMaxX;
    maxY = newMaxY;
    maxZ = newMaxZ;
  }

  void setFrom(Aabb other) {
    setValues(
      other.minX,
      other.minY,
      other.minZ,
      other.maxX,
      other.maxY,
      other.maxZ,
    );
  }

  void translate(double x, double y, double z) {
    minX += x;
    maxX += x;
    minY += y;
    maxY += y;
    minZ += z;
    maxZ += z;
  }

  bool intersects(Aabb other) =>
      minX < other.maxX &&
      maxX > other.minX &&
      minY < other.maxY &&
      maxY > other.minY &&
      minZ < other.maxZ &&
      maxZ > other.minZ;

  bool intersectsBounds(
    double otherMinX,
    double otherMinY,
    double otherMinZ,
    double otherMaxX,
    double otherMaxY,
    double otherMaxZ,
  ) =>
      minX < otherMaxX &&
      maxX > otherMinX &&
      minY < otherMaxY &&
      maxY > otherMinY &&
      minZ < otherMaxZ &&
      maxZ > otherMinZ;

  bool intersectsVoxel(int x, int y, int z) => intersectsBounds(
    x.toDouble(),
    y.toDouble(),
    z.toDouble(),
    x + 1.0,
    y + 1.0,
    z + 1.0,
  );
}
