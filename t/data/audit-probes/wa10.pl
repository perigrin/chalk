my @a = (1,2,3); @a = reverse @a; @a = map { $_ + 1 } @a; print "@a\n";
