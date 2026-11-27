our $g = 1; my $c = sub { $g }; { local $g = 2; print $c->() } print $c->(), "\n";
