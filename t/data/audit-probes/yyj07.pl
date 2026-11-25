my @a=(1,2); my $f = sub { push @a, scalar(@a)+1; scalar @a }; $f->(); print $f->(), "@a\n";
