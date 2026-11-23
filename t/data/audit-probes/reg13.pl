my $x=1; sub f { $x=5; 1 } my @l=($x, f(), $x); print "@l\n";
