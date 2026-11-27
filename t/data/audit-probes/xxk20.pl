my @a = ("ab","cd"); my $n = 0; $n += s/[ac]/_/ for @a; print "$n@a\n";
