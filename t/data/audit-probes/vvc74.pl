our $x = 1; my $y = 5; *x = \$y; my $c = sub { $x++ }; $c->(); print "$y\n";
