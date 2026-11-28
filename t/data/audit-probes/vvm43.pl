our @a = (1,2,3); my $c = sub { "@a" }; { local @a = (3); print $c->(), ";" } print $c->(), "\n";
