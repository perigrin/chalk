my $x = 1; my $c; { my $x = 2; $c = sub { $x } } $x = 9; print $c->(), "\n";
