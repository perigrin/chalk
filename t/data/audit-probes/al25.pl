my @a = (1); my $f = sub { push @a, 2 }; $f->(); print scalar(@a), "\n";
