sub f { $_[0] = 5; 1 } my $x=1; my @l = ($x, f($x), $x); print "@l\n";
