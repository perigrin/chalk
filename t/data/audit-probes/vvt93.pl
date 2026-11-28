sub f { $_[0]++; 0 } my @t; my @a = (1,2,3); for (@a) { push @t, $_ . f($_) . $_ } print "@t\n";
