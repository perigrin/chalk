my @a = (1,2,3); $_ = 0 for grep { $_ > 1 } @a; print "@a\n";
