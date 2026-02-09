int fibonacci(int n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

int factorial(int n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

int main() {
    if (fibonacci(0) != 0) return 1;
    if (fibonacci(1) != 1) return 2;
    if (fibonacci(10) != 55) return 3;
    if (factorial(5) != 120) return 4;
    if (factorial(1) != 1) return 5;
    return 0;
}
