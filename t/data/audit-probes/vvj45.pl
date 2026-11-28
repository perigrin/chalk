my @a = (1,2,3); my @b = grep { 1 } @a; $_ = 0 for @b; print "@a\n";
