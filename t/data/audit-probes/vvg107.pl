my $x = 1; my $c = sub { $x }; { my $x = 2; print $c->() } print "\n";
