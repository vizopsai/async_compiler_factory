int counter = 0;

void increment() {
    counter = counter + 1;
}

int get_counter() {
    return counter;
}

int main() {
    if (get_counter() != 0) return 1;
    increment();
    increment();
    increment();
    if (get_counter() != 3) return 2;
    counter = 100;
    if (get_counter() != 100) return 3;
    return 0;
}
