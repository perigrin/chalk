our $g=1; eval { local $g = 2; my $x = "abc"; my $y = 0 + $x; exit_now() }; sub exit_now { die "e\n" } print "$g\n";
