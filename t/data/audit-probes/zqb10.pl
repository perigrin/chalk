our $x=1; my $r=\$x; sub f { local $x=5; $$r } print f(), "\n";
