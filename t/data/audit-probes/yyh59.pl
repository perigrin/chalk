my @a = (1,2,3); my $r = push(@a, 4, 5); my $u = unshift(@a, 0); my @sp = splice(@a, 1, 2); my $sl = splice(@a, 0, 2); print "$r$u@sp$sl@a\n";
