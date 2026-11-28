my $i = 9; my $c = sub { $i }; my @l; for $i (1..3) { push @l, $c->() } print "@l $i\n";
