int add(int a, int b) {
    return a + b;
}

int square(int x) {
    return x * x;
}

int max(int a, int b) {
    if (a > b) return a;
    return b;
}

int main() {
    if (add(3, 4) != 7) return 1;
    if (square(5) != 25) return 2;
    if (max(10, 20) != 20) return 3;
    if (max(30, 15) != 30) return 4;
    return 0;
}
