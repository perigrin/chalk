our $g = 1; eval { for my $x (1,2) { local $g = 5; die "m\n" if $x == 2 } }; print "$g [$@]\n";
