our $g = 1; sub t { local $g = 2; my $v = eval { $g = 3; die "x\n" }; $g } print t(), "$g\n";
