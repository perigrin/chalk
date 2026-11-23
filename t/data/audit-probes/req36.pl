our $g=1; sub f { my $z=shift; local $g=2; return 7 if $z; 1/$z } eval { f(0) }; print "$g\n";
