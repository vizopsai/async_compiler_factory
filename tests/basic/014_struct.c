struct Point {
    int x;
    int y;
};

int distance_sq(struct Point a, struct Point b) {
    int dx = a.x - b.x;
    int dy = a.y - b.y;
    return dx * dx + dy * dy;
}

int main() {
    struct Point p;
    p.x = 3;
    p.y = 4;
    if (p.x != 3) return 1;
    if (p.y != 4) return 2;

    struct Point origin;
    origin.x = 0;
    origin.y = 0;

    int d = distance_sq(p, origin);
    if (d != 25) return 3;

    return 0;
}
