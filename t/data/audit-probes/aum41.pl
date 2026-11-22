my @a=(1); my $f = sub { push @a, 2; 0 }; my $n = @a; my @c = ($n, $f->(), scalar(@a)); print "@c\n";
