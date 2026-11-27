my $x = 1; my $c = sub { $x++ }; print "$x", $c->(), "$x", "\n";
