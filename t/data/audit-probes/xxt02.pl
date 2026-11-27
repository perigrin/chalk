my $x = 1; my $c = sub { $x = 5 }; my $y = $x + $c->() + $x; print "$y\n";
