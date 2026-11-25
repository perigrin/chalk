our $g=1; my $c=sub { local $g=2; die "x\n" }; eval { $c->() }; print "$g\n";
