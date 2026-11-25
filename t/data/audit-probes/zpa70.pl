my @a=("a","b"); my @b=map { $_ .= "!" ; $_ } @a; print "@a|@b\n";
