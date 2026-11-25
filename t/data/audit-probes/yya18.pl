my $x=1; sub f { my ($p)=@_; $p++; "$p$_[0]" } print f($x), "\n";
