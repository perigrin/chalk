sub f { local $_ = $_[0]; s/a/b/; $_ } my $x="a"; print f($x), $x, "\n";
