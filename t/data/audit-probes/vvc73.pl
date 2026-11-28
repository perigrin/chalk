our $x = 1; my $y = 5; my $c = sub { $x }; *x = \$y; print $c->(), "\n";
