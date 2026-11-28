my @a = (1); my $z = 0; eval { push @a, 2, 1 / $z }; print "@a\n";
