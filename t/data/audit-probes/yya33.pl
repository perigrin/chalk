my $x=1; sub f { my ($p)=@_; undef $_[0]; defined $p ? $p : "u" } print f($x), defined $x ? "d" : "u", "\n";
