my $x = 1; my $c = sub { $x = 3; 2 }; my @l = ($x, $c->(), $x); print "@l\n";
