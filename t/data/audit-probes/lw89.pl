my @a=(1,2); my @m = map { $_ .= "x"; last if 0; $_ } @a; print "@a @m\n";
