my $n = 0; my $c; $c = sub { $n++; $c->() if $n < 3; $n }; my @l = ($n, $c->(), $n); print "@l\n";
