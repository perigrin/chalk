my @a=(1,2,3); my @g = grep { $_ > 1 } @a; $_*=10 for @g; print "@a\n";
