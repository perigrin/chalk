my $str = "a,b,c"; my $n = () = split /,/, $str; my ($f) = split /,/, $str; my $c = split /,/, $str; my @p = split /,/, $str, 2; print "$n$f$c@p\n";
