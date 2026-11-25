my $x=1; sub g { $_[0]=9 } sub f { g(@_); my ($p)=@_; $p } print f($x), "$x\n";
