our $n=0; my $z=0; sub f { $n=7; my $u = $_[0] % $z; $n=8; 1 } eval { f(1) }; print "$n\n";
