my $s = "abc"; my $t = $s =~ y/abc/xyz/r; my $n = ($t =~ tr/x-z//); print "$t$n\n";
