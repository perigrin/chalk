our @a = (1,2); sub f :lvalue { $a[0] } { local @a = (7, 8); f() = 5; print "@a;" } print "@a\n";
