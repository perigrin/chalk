my $x="a\n"; sub f { my ($p)=@_; chomp(@_); length($p) } print f($x), length($x), "\n";
