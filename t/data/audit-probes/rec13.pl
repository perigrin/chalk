our $g=1; sub f { local $g=2; my $z=shift; return 1/$z } for my $i (0,1) { eval { f($i) }; print $g } print "\n";
