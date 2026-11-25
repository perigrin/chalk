my $x="ab"; sub t { $_[0] =~ tr/a/z/ } sub f { my ($p)=@_; t($_[0]); $p } print f($x), "$x\n";
