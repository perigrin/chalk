my $x = 1; my $c = sub { my $o = $x; $_[0] = 9; "$o$x" }; print $c->($x), "\n";
