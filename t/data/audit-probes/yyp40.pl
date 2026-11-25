my $x="ab"; sub f { my ($p)=@_; my $c = ($_[0] =~ tr/a/z/); "$p$c" } print f($x), "$x\n";
