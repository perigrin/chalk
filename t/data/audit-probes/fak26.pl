my @a=(1); my $p=sub { push @a,9; scalar @a }; print scalar(@a), $p->(), scalar(@a), "\n";
