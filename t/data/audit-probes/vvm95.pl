our @a = (1,2); { no strict 'refs'; local ${"a"}[0] = 7; print "@a;" } print "@a\n";
