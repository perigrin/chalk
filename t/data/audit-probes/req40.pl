our $g=1; sub f { local $g=2; my $q = eval { 1/$_[0] }; $g } print f(0), $g, "\n";
