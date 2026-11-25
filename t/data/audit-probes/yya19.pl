my @a=(1,2); sub f { my ($p)=@_; @a=(7,8); $p } print f($a[0]), "\n";
