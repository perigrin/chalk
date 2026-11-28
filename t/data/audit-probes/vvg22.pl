my $x = 1; sub mk { my $r = \$_[0]; $r } my $r = mk($x); $$r = 5; print "$x\n";
