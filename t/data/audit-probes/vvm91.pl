our @a = (1,2); { no strict 'refs'; local @{"a"} = (7); print "@a;" } print "@a\n";
