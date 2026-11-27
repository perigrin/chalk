my $x=1; sub f { my ($p)=@_; my $r=\@_; $r->[0]=9; $p } print f($x), "$x\n";
