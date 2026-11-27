our $x = 1; my @a = (4,5); *x = \$a[1]; $x++; print "@a\n";
