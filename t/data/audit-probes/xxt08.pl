my $x = 1; my $c = sub { $x++ }; my $s = sprintf "%d%d%d", $x, $c->(), $x; print "$s\n";
