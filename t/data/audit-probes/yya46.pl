my $x=1; sub f { my ($p)=@_; $x=9; return $p + $_[0] } print f($x), "\n";
