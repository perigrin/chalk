my $x = 1; my $c = sub { $_[0] = 9; $x }; print $c->($x), $x, "\n";
