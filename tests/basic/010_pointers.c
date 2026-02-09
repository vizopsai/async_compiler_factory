int main() {
    int x = 42;
    int *p = &x;
    if (*p != 42) return 1;

    *p = 100;
    if (x != 100) return 2;

    int a = 10;
    int b = 20;
    int *pa = &a;
    int *pb = &b;
    int temp = *pa;
    *pa = *pb;
    *pb = temp;
    if (a != 20) return 3;
    if (b != 10) return 4;

    return 0;
}
