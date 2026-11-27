sub f { my ($p) = @_; $p } my $x = 1; my $c = \&f; $x = 2; print $c->($x), "\n";
