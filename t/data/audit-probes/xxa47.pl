sub f { \$_[0] } my $x=1; my $r = f($x); $$r = 3; print "$x\n";
