int main() {
    int a = 10 + 20;
    if (a != 30) return 1;

    int b = 50 - 17;
    if (b != 33) return 2;

    int c = 6 * 7;
    if (c != 42) return 3;

    int d = 100 / 4;
    if (d != 25) return 4;

    int e = 17 % 5;
    if (e != 2) return 5;

    return 0;
}
