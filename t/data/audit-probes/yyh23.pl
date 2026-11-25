sub f { @_ } sub g { (4,5,6) } sub h { return (4,5,6) } my $a1 = f(7,8); my $b1 = g(); my $c1 = h(); print "$a1$b1$c1\n";
