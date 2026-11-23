my $x=1; my $r=\$x; $$r=5; print "$x\n"; $x=6; print "$$r\n";
