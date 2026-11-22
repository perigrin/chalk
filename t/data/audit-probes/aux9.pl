our $g=1; eval { local $g=2; my $x = "a" x -1; my @e = (1) x 2; my $v = 1 << 70; my $q = 5 ** 2; die "end\n" }; print "$g\n";
