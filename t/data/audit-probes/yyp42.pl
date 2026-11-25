my $x="ab"; sub f { $_[0] =~ tr/a/z/; my ($p)=@_; $p } print f($x), "$x\n";
