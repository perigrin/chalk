sub f { $_++; 0 } my @a = (1,2,3); my @t; for (@a) { push @t, $_ . f() . $_ } print "@t\n";
