my @a = ("ab","cd"); my @b = map { tr/a-d/A-D/r } @a; print "@a|@b\n";
