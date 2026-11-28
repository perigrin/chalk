my @a = ("ab", "cd"); my @b = grep { s/a/z/ } @a; print "@a|@b\n";
