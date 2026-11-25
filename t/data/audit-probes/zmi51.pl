my $s="a.b.c"; my @p=split /\./, $s; my ($h,$t)=split /\./, $s, 2; print scalar(@p), "$h|$t\n";
