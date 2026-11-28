sub f { $_[0]++; 0 } my @a = (1,2,3); my @t = map { ($_, f($_), $_) } @a; print "@t\n";
