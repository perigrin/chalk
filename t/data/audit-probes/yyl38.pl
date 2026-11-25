my $s = "a,b;c"; my @p = split /[,;]/, $s; my $j = join "+", @p; my ($h, @t) = split /,|;/, $s; my $n = scalar(split /[,;]/, $s); print "$j$h@t$n\n";
