my $x=1; sub f { my ($p,@r)=@_; $x=9; "$p@r" } print f(0,$x), "\n";
