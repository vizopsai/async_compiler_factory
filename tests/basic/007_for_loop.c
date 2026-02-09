int main() {
    int sum = 0;
    int i;
    for (i = 0; i < 10; i = i + 1) {
        sum = sum + i;
    }
    if (sum != 45) return 1;

    int product = 1;
    for (i = 1; i <= 5; i = i + 1) {
        product = product * i;
    }
    if (product != 120) return 2;

    return 0;
}
