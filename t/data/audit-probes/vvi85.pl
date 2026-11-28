$_ = "abc"; my $n = tr/a-c//; my $t = y/a/z/r; print "$n$t$_\n";
