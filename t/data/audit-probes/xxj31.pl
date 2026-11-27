$_ = "abc"; my $n = tr/a-c//; my $m = tr/a/A/; print "$n$m$_\n";
