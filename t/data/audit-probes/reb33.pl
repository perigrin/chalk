our $g=1; sub f { local $g=2; my $z = shift; 1/$z } eval { f(0) }; print "$g ", ($@?1:0), "\n";
