my $x="ab"; sub f { my ($p)=@_; $_[0] =~ tr/a/z/; $p } print f($x), "$x\n";
