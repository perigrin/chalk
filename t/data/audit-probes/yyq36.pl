my $s="abc"; my $r=\substr($s,0,1); $$r = "ZZ"; $$r = "Q"; print "$s\n";
