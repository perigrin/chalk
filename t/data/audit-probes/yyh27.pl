sub f { return map { $_ * 2 } @_ } sub g { grep { $_ > 1 } @_ } my $n = f(1,2,3); my $m = g(1,2,3); print "$n$m\n";
