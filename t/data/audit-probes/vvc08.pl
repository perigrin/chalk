our $x = 1; my @a = (4,5); *x = \$a[1]; $a[1] = 9; print "$x\n";
