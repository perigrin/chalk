my $x=1; sub f { return \$_[0] } my $r=f($x); $$r=9; print "$x\n";
