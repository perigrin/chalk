sub f { my ($p,%o)=@_; $p . join ",", map { "$_=$o{$_}" } sort keys %o } my @l=(b=>2); print f(1,@l,c=>3), "\n";
