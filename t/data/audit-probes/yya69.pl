my $x=1; sub f { my $r=\$_[0]; sub { $$r } } my $c=f($x); $x=9; print $c->(), "\n";
