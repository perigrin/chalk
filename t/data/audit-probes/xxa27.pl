sub f { my $n = @_; $_[$n-1] = "L"; } my ($a1,$b1,$c1)=(1,2,3); f($a1,$b1,$c1); print "$a1$b1$c1\n";
