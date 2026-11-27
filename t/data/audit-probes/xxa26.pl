sub f { my $p = $_[0]; $_[0] = "w"; $p . $_[0] } my $x="o"; print f($x), $x, "\n";
