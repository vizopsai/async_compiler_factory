int main() {
    int arr[5];
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;
    arr[3] = 40;
    arr[4] = 50;

    int sum = 0;
    int i;
    for (i = 0; i < 5; i = i + 1) {
        sum = sum + arr[i];
    }
    if (sum != 150) return 1;

    if (arr[2] != 30) return 2;

    arr[2] = 99;
    if (arr[2] != 99) return 3;

    return 0;
}
