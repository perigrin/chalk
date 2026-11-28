my ($x, $y); my $c = sub { $x = 9; 0 }; my @l = ((($x, $y) = (7,8)), $c->()); print "@l\n";
