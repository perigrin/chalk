sub f { $_++; 0 } my @a = (1,2,3); my @t = map { ($_, f(), $_) } @a; print "@t\n";
