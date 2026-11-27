sub f { my $c = \@_; sub { "@$c" } } my @a = (1,2); my $c = f(@a); $a[0] = 9; print $c->(), "\n";
