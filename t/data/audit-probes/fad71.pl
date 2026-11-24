our $g=1; sub f { local $g=2; my @a=(1); splice(@a, 5, 1); my $r = \&{"nosuch"}; $r->() } eval { f() }; print "$g ", $@?1:0, "\n";
