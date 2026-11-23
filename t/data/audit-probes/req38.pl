our $g=1; sub f { for my $i (1) { local $g=2; my $q = 1/$_[0] } } eval { f(0) }; print "$g\n";
