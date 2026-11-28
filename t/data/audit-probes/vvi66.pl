my $s = "abc"; my $t = $s; $t .= "d"; my $u = $t; $u =~ tr/a/z/; print "$s$t$u\n";
