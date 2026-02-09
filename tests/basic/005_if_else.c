int main() {
    int x = 10;
    int result = 0;

    if (x > 5) {
        result = 1;
    } else {
        result = 2;
    }
    if (result != 1) return 1;

    if (x < 5) {
        result = 10;
    } else {
        result = 20;
    }
    if (result != 20) return 2;

    if (x == 10) {
        result = 100;
    }
    if (result != 100) return 3;

    return 0;
}
