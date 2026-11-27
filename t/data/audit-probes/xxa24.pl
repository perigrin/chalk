sub f { my @c = @_; $_[0] = "w"; "@c" } my $x="o"; print f($x), $x, "\n";
