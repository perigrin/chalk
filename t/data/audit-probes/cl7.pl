my $x = 1; my $s = sub { $x = $_[0] }; my $g = sub { $x }; $s->(5); my $y = $x; $s->(6); print "$y ", $g->(), " $x\n";
