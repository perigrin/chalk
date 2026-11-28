my @a = (1,2,3); sub ret { @a } my @b = ret(); $b[0] = 9; my ($f) = ret(); my $n = ret(); print "@a$f$n\n";
