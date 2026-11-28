my $x = 1; my $y = 1; my $c = sub { $x = 3; 2 }; my @l = (($y && $x), $c->()); print "@l\n";
