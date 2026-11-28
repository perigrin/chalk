our $x = 1; sub f { local $x = $_[0]; sub { $x } } my $c = f(5); print $c->(), "\n";
