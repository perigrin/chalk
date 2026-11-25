my $x=1; sub f { my ($p)=@_; my @t = map { $_ = 9 } $_[0]; $p } print f($x), "$x\n";
