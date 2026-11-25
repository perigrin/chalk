my $x=1; sub f { my $n=@_; shift; my ($p)=@_; $x=9; "$n$p" } print f(0,$x), "\n";
