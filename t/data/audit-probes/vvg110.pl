our $x = 1; my $c = sub { $x }; $x = 5; print $c->(), "\n";
