my $x=1; sub f { my ($p)=@_; $_[0].="z"; $p } print f($x), "$x\n";
