sub f { my ($p) = @_; $_[0] = "w"; $p } my $x="o"; print f($x), $x, "\n";
