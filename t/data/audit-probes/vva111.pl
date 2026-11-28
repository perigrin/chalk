our $x = 1; sub f { local $x = $_[0]; my $r = \$x; sub { $$r } } my $c = f(5); print $c->(), "$x\n";
