sub f { $_[0]++; 0 } my @t; my @a = (1,2,3); push @t, $_ . f($_) . $_ for @a; print "@t\n";
