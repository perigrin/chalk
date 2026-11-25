my @a = (1); eval { push @a, 2; die "x\n"; push @a, 3; }; my %h; eval { $h{a} = 1; die "x\n" }; print "@a", scalar(keys %h), "\n";
