our $x=1; my $c=sub { $x }; sub f { local $x=5; $c->() } print f(), "\n";
