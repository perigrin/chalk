my $s = "a,b,c"; my ($f, @r) = split /,/, $s; $s =~ s/,//g; print "$f@r$s\n";
