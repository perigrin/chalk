my $x="ab"; sub f { my $p=$_[0]; $_[0] =~ tr/a/z/; $p . $_[0] } print f($x), "$x\n";
