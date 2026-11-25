my $x=1; sub f { my ($p)=@_; return \$p } my $r=f($x); $$r=9; print "$x\n";
