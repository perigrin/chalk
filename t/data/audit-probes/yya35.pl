my $x="ab"; sub f { my ($p)=@_; chop $_[0]; $p } print f($x), "$x\n";
