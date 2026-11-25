my $x=1; my $c = sub { $x = 4; $_[0] }; print $c->($x), "\n";
