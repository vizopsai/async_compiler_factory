int main() {
    int a = 0xFF;
    int b = 0x0F;

    if ((a & b) != 0x0F) return 1;
    if ((a | b) != 0xFF) return 2;
    if ((a ^ b) != 0xF0) return 3;
    if ((~0) != -1) return 4;

    if ((1 << 4) != 16) return 5;
    if ((16 >> 2) != 4) return 6;

    return 0;
}
