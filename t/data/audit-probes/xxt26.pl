our $x = 1; my $c = sub { local $x = 5; $x }; my @l = ($x, $c->(), $x); print "@l\n";
