import 'package:flutter_test/flutter_test.dart';

void main() {
  test('X-axis horizontal wrapping logic test', () {
    double playerX = 1.2; // Went beyond right edge (1.1)
    if (playerX > 1.1) playerX = -1.1;
    expect(playerX, -1.1);

    playerX = -1.2; // Went beyond left edge (-1.1)
    if (playerX < -1.1) playerX = 1.1;
    expect(playerX, 1.1);

    playerX = 0.5; // Stayed within bounds
    if (playerX < -1.1) playerX = 1.1;
    if (playerX > 1.1) playerX = -1.1;
    expect(playerX, 0.5);
  });
}
