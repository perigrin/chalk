my $x="ab"; sub f { my ($p)=@_; $_[0] =~ s/a/z/; $p } print f($x), "$x\n";
