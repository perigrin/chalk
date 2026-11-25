my $x=1; sub f { my ($p)=@_; my @t = map { $_++ } @_; $p } print f($x), "$x\n";
