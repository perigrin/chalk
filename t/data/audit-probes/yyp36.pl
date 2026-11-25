my $x; sub f { my ($p)=@_; $_[0] //= 5; defined $p ? $p : "u" } print f($x), "$x\n";
