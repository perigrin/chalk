our $x = 1; my $c = sub { $x }; { local $x = 2; print $c->() } print $c->(), "\n";
