our $g=1; sub f { local $g=2; my @a=(1); my $i=shift; splice(@a,$i,1); 1 } eval { f(5) }; print "$g\n";
