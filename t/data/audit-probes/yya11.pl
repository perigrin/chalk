my $x=1; sub f { my (%h)=@_; $x=9; $h{a} } print f(a=>$x), "\n";
