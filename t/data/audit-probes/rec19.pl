our $_x=1; sub f { local $_=7; my $z=shift; 1/$z } $_="t"; eval { f(0) }; print "$_\n";
