my $s="a\n\n"; { local $/=""; my $n=chomp($s); print "$n [$s]\n"; }
