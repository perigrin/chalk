our $g=1; sub f { my $z=shift; my $q=1/$z; local $g=2; return $q } eval { f(0) }; print "$g\n";
