sub f { sub { $_[0] } } my $x=1; my $c = f($x); print defined $c->() ? "d" : "u", "\n";
