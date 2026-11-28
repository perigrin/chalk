my $s = "abcabc"; my $n = $s =~ tr/a//; my $m = ($s =~ tr/a/z/); print "$n$m$s\n";
