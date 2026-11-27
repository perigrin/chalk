our $x = 1; my $c = sub { $x = 5; 0 }; my @l = ($x, $c->(), $x); print "@l\n";
