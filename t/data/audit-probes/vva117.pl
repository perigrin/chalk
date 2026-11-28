our @a = (1,2); { local ($x, @a) = (5, 6, 7); print "$x@a" } print defined $x ? "d" : "u", "@a\n";
