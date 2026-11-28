my $s = "abc"; my $t = $s =~ tr/a-c/A-C/r; my $u = $s =~ tr/a/z/r; print "$s$t$u\n";
