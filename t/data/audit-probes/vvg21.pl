my $x = 1; sub mk { \$_[0] } my $r = mk($x); $$r = 5; print "$x\n";
