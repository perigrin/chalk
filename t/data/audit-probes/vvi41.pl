my $s = "abc"; my $r = \substr($s, 1, 1); $$r = "ZZ"; $$r = "y"; print "$s\n";
