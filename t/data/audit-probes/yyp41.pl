my $x="ab"; sub f { my ($p)=@_; $_[0] =~ y/b/z/; $p } print f($x), "$x\n";
