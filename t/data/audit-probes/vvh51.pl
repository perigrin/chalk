my $x = 1; my $c = sub { $x = 2; die "z\n" }; eval { $c->() }; print "$x$@";
