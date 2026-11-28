my $n = 0; my @a = (1,2,3); eval { map { $_ *= 2; die "x\n" if $_ == 4 } @a }; print "@a\n";
