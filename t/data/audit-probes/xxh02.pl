sub f { my ($p) = @_; g2(\@_); $p . $_[0] } sub g2 { $_[0][0] = "w" } my $x = "o"; print f($x), $x, "\n";
