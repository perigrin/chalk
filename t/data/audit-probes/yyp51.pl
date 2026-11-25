my $x=1; sub f { my ($p)=@_; $_[$#_]=9; $p } print f($x), "$x\n";
