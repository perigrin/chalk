local $/ = undef; my $s = "a\nb\n"; open(my $in, "<", \$s); my $all = <$in>; print length($all), "\n";
