our $x = 1; sub rd { $x } my $c = sub { local $x = 5; rd() }; my @l = (rd(), $c->(), rd()); print "@l\n";
