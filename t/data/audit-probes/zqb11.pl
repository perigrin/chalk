our $x=1; my $r=\$x; sub f { local $x=5; $$r=7; $x } print f(), $x, "\n";
