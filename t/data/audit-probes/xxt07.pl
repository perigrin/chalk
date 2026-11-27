my $x = 1; my $c = sub { $x++ }; my $s = join ",", $x, $c->(), $x; print "$s\n";
