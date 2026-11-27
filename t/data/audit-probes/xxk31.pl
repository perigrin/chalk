my $s = "hello"; my $r = \substr($s, 1, 2); $$r = "XYZ"; print "$s\n";
