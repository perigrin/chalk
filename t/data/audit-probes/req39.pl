our $g=1; sub f { if ($_[1]) { local $g=2; my $q = 1/$_[0]; } 5 } eval { f(0,1) }; print "$g\n";
