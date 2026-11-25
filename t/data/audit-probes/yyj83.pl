my $s = "abc"; my $r = \substr($s, 1, 1); $$r = "XYZ"; print "$s\n";
