sub f { my $r = \$_[0]; $$r = 8 } my $x = 1; f($x); print "$x\n";
