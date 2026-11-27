my $x = 1; my $c = sub { $x = 5; 2 }; my $y = $x ** $c->(); my $z = $x <=> $c->(); print "$y$z\n";
